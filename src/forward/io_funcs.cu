/*
 *
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "netcdf.h"
#include "sacLib.h"

#include "fdlib_math.h"
#include "fdlib_mem.h"
#include "constants.h"
#include "fd_t.h"
#include "io_funcs.h"
#include "cuda_common.h"
#include "alloc.h"

/*
 * read in station list file and locate station
 */
int
io_recv_read_locate(gd_t      *gd,
                    iorecv_t  *iorecv,
                    int       nt_total,
                    int       num_of_vars,
                    int       num_of_mpiprocs_z,
                    char      *in_filenm,
                    MPI_Comm  comm,
                    int       myid)
{
  FILE *fp;
  char line[500];

  iorecv->total_number = 0;
  if (!(fp = fopen (in_filenm, "rt")))
	{
    
    fprintf(stdout,"#########         ########\n");
    fprintf(stdout,"######### Warning ########\n");
    fprintf(stdout,"#########         ########\n");
    fprintf(stdout,"Cannot open input station file %s\n", in_filenm);
    
	  fflush (stdout);
	  return 0;
	}

  int total_point_x = gd->total_point_x;
  int total_point_y = gd->total_point_y;
  int total_point_z = gd->total_point_z;
  // number of station
  int num_recv;

  io_get_nextline(fp, line, 500);
  sscanf(line, "%d", &num_recv);

  //fprintf(stdout, "-- nr=%d\n", nr);

  // check fail in the future
  iorecv_one_t *recvone = (iorecv_one_t *)malloc(num_recv * sizeof(iorecv_one_t));

  // read coord and locate

  int ir=0;
  int nr_this = 0; // in this thread
  int recv_by_coords = 0;

  int *flag_coord = (int *) malloc(sizeof(int) * num_recv);
  int *flag_depth = (int *) malloc(sizeof(int) * num_recv);

  float *all_coords = (float *) malloc(sizeof(float) * CONST_NDIM * num_recv);
  int *all_index = (int *) malloc(sizeof(int) * CONST_NDIM * num_recv);
  float *all_inc = (float *) malloc(sizeof(float) * CONST_NDIM * num_recv);

  for (ir=0; ir<num_recv; ir++)
  {
    // read one line
    io_get_nextline(fp, line, 500);

    // get values
    sscanf(line, "%s %d %d %g %g %g", 
              recvone[ir].name, &flag_coord[ir], &flag_depth[ir], &all_coords[3*ir+0], &all_coords[3*ir+1], &all_coords[3*ir+2]);

    if(flag_coord[ir] == 1)
    {
      recv_by_coords += 1;
    }

    if(num_of_mpiprocs_z >=2 && flag_depth[ir] == 1)
    {
      fprintf(stderr,"station not yet implement z axis depth to coord(index) with z axis mpi >= 2\n");
      fflush(stderr); exit(1);
    }
  }

  // by axis
  // computation is big, use GPU 

  int *flag_coord_d = NULL; 
  int *flag_depth_d = NULL;
  
  int *all_index_tmp = NULL;
  float *all_inc_tmp = NULL;

  float *all_coords_d = NULL;
  int *all_index_d = NULL;
  float *all_inc_d = NULL;
  if (recv_by_coords > 0)
  {
    //recv_coords is physical coords
    //computational is big, use GPU
    fprintf(stdout,"recv has physical coords, maybe computational big, use GPU\n");
    fprintf(stdout,"recv_by_coords is %d\n",recv_by_coords);
    gd_t gd_d;
    init_gd_device(gd,&gd_d);

    all_index_tmp  = (int *)   malloc(sizeof(int) * CONST_NDIM * num_recv);
    all_inc_tmp    = (float *) malloc(sizeof(float) * CONST_NDIM * num_recv);

    flag_coord_d  = (int *)    cuda_malloc(sizeof(int)*num_recv);
    flag_depth_d  = (int *)   cuda_malloc(sizeof(int)*num_recv);
    all_coords_d = (float *) cuda_malloc(sizeof(float)*num_recv*CONST_NDIM);
    all_index_d  = (int *)   cuda_malloc(sizeof(int)*num_recv*CONST_NDIM);
    all_inc_d    = (float *) cuda_malloc(sizeof(float)*num_recv*CONST_NDIM);
    CUDACHECK(cudaMemcpy(flag_coord_d,flag_coord,sizeof(int)*num_recv,cudaMemcpyHostToDevice));
    CUDACHECK(cudaMemcpy(flag_depth_d,flag_depth,sizeof(int)*num_recv,cudaMemcpyHostToDevice));
    CUDACHECK(cudaMemcpy(all_coords_d,all_coords,sizeof(float)*num_recv*CONST_NDIM,cudaMemcpyHostToDevice));

    dim3 block(256);
    dim3 grid;
    grid.x = (num_recv+block.x-1) / block.x;
    recv_depth_to_axis<<<grid, block>>> (all_coords_d, num_recv, gd_d, 
                         flag_coord_d, flag_depth_d, comm, myid);
    CUDACHECK(cudaDeviceSynchronize());
    grid.x = (num_recv+block.x-1) / block.x;
    recv_coords_to_glob_indx<<<grid, block>>> (all_coords_d, all_index_d, 
                              all_inc_d, num_recv, gd_d, flag_coord_d, comm, myid);
    CUDACHECK(cudaDeviceSynchronize());
    CUDACHECK(cudaMemcpy(all_coords,all_coords_d,sizeof(float)*num_recv*CONST_NDIM,cudaMemcpyDeviceToHost));
    CUDACHECK(cudaMemcpy(all_index_tmp,all_index_d,sizeof(int)*num_recv*CONST_NDIM,cudaMemcpyDeviceToHost));
    CUDACHECK(cudaMemcpy(all_inc_tmp,all_inc_d,sizeof(float)*num_recv*CONST_NDIM,cudaMemcpyDeviceToHost));

    // reduce must after gpu calcu finish
    // due to gpu thread is not synchronization
    // reduce global index and shift values from temp pointer value
    MPI_Allreduce(all_index_tmp, all_index, num_recv*CONST_NDIM, MPI_INT, MPI_MAX, comm);
    MPI_Allreduce(all_inc_tmp, all_inc, num_recv*CONST_NDIM, MPI_FLOAT, MPI_SUM, comm);
    //free temp pointer
    dealloc_gd_device(gd_d);
    CUDACHECK(cudaFree(flag_coord_d));
    CUDACHECK(cudaFree(flag_depth_d));
    CUDACHECK(cudaFree(all_coords_d));
    CUDACHECK(cudaFree(all_index_d));
    CUDACHECK(cudaFree(all_inc_d));
    free(all_index_tmp);
    free(all_inc_tmp);
  }

  for (ir=0; ir<num_recv; ir++)
  {
    // conver minus shift to plus to use linear interp with all grid in this thread
    //    there may be problem if the receiver is located just bewteen two mpi block
    //    we should exchange data first then before save receiver waveform
    if(flag_coord[ir] == 1)
    {
      if (all_inc[3*ir+0] < 0.0) {
        all_inc[3*ir+0] = 1.0 +all_inc[3*ir+0];
        all_index[3*ir+0] -= 1;
      }
      if (all_inc[3*ir+1] < 0.0) {
        all_inc[3*ir+1] = 1.0 + all_inc[3*ir+1];
        all_index[3*ir+1] -= 1;
      }
      if (all_inc[3*ir+2] < 0.0) {
        all_inc[3*ir+2] = 1.0 + all_inc[3*ir+2];
        all_index[3*ir+2] -= 1;
      }
    }

    // by grid index
    if (flag_coord[ir] == 0)
    {
      // need minus 1. C index start from 1.
      all_coords[3*ir+0] -= 1;
      all_coords[3*ir+1] -= 1;

      // if sz is relative to surface, convert to normal index
      if (flag_depth[ir] == 1) {
        all_coords[3*ir+2] = gd->gnk2 - all_coords[3*ir+2];
      } else {
        all_coords[3*ir+2] -= 1;
      }

      // do not take nearest value, but use smaller value
      all_index[3*ir+0] = (int) (all_coords[3*ir+0]);
      all_index[3*ir+1] = (int) (all_coords[3*ir+1]);
      all_index[3*ir+2] = (int) (all_coords[3*ir+2]);
      all_inc[3*ir+0] = all_coords[3*ir+0] - all_index[3*ir+0] ;
      all_inc[3*ir+1] = all_coords[3*ir+1] - all_index[3*ir+1] ;
      all_inc[3*ir+2] = all_coords[3*ir+2] - all_index[3*ir+2] ;
      // check recv index whether outside
      if(all_index[3*ir+0]<0 || all_index[3*ir+0] > total_point_x)
      {
        all_index[3*ir+0] = -1000;
      }
      if(all_index[3*ir+1]<0 || all_index[3*ir+1] > total_point_y)
      {
        all_index[3*ir+1] = -1000;
      }
      if(all_index[3*ir+2]<0 || all_index[3*ir+2] > total_point_z)
      {
        all_index[3*ir+2] = -1000;
      }
    }
    int ix = all_index[3*ir+0];
    int iy = all_index[3*ir+1];
    int iz = all_index[3*ir+2];

    float rx_inc= all_inc[3*ir+0];
    float ry_inc= all_inc[3*ir+1];
    float rz_inc= all_inc[3*ir+2];

    float rx = all_coords[3*ir+0];
    float ry = all_coords[3*ir+1];
    float rz = all_coords[3*ir+2];
    if (gd_info_gindx_is_inner(ix,iy,iz,gd) == 1)
    {
      // convert to local index w ghost
      int i_local = gd_info_indx_glphy2lcext_i(ix,gd);
      int j_local = gd_info_indx_glphy2lcext_j(iy,gd);
      int k_local = gd_info_indx_glphy2lcext_k(iz,gd);

      // get coord
      if (flag_coord[ir] == 0)
      {
        rx = gd_coord_get_x(gd,i_local,j_local,k_local);
        ry = gd_coord_get_y(gd,i_local,j_local,k_local);
        rz = gd_coord_get_z(gd,i_local,j_local,k_local);
      }

      int ptr_this = nr_this * CONST_NDIM;
      iorecv_one_t *this_recv = recvone + nr_this;

      sprintf(this_recv->name, "%s", recvone[ir].name);

      // get coord
      this_recv->x = rx;
      this_recv->y = ry;
      this_recv->z = rz;
      // set point and shift
      this_recv->i=i_local;
      this_recv->j=j_local;
      this_recv->k=k_local;
      this_recv->di = rx_inc;
      this_recv->dj = ry_inc;
      this_recv->dk = rz_inc;

      this_recv->indx1d[0] = i_local   + j_local     * gd->siz_iy + k_local * gd->siz_iz;
      this_recv->indx1d[1] = i_local+1 + j_local     * gd->siz_iy + k_local * gd->siz_iz;
      this_recv->indx1d[2] = i_local   + (j_local+1) * gd->siz_iy + k_local * gd->siz_iz;
      this_recv->indx1d[3] = i_local+1 + (j_local+1) * gd->siz_iy + k_local * gd->siz_iz;
      this_recv->indx1d[4] = i_local   + j_local     * gd->siz_iy + (k_local+1) * gd->siz_iz;
      this_recv->indx1d[5] = i_local+1 + j_local     * gd->siz_iy + (k_local+1) * gd->siz_iz;
      this_recv->indx1d[6] = i_local   + (j_local+1) * gd->siz_iy + (k_local+1) * gd->siz_iz;
      this_recv->indx1d[7] = i_local+1 + (j_local+1) * gd->siz_iy + (k_local+1) * gd->siz_iz;

      //fprintf(stdout,"== ir_this=%d,name=%s,i=%d,j=%d,k=%d\n",
      //      nr_this,sta_name[nr_this],i_local,j_local,k_local); fflush(stdout);

      nr_this += 1;
    }
  }
  if(myid==0)
  {
    for (ir=0; ir<num_recv; ir++)
    {
      if(all_index[3*ir+0] == -1000 || all_index[3*ir+1] == -1000 || 
         all_index[3*ir+2] == -1000)
      {
        fprintf(stdout,"#########         ########\n");
        fprintf(stdout,"######### Warning ########\n");
        fprintf(stdout,"#########         ########\n");
        fprintf(stdout,"recv_number[%d] physical coordinates are outside calculation area !\n",ir);
      }
    }
  }

  fclose(fp);
 
  iorecv->total_number = nr_this;
  iorecv->recvone      = recvone;
  iorecv->max_nt       = nt_total;
  iorecv->ncmp         = num_of_vars;

  // malloc seismo
  for (int ir=0; ir < iorecv->total_number; ir++)
  {
    recvone = iorecv->recvone + ir;
    recvone->seismo = (float *) malloc(num_of_vars * nt_total * sizeof(float));
  }
  free(all_index);
  free(all_inc);
  free(all_coords);
  free(flag_coord);
  free(flag_depth);
  return 0;
}

int
io_line_locate(gd_t *gd,
               ioline_t *ioline,
               int    num_of_vars,
               int    nt_total,
               int    number_of_receiver_line,
               int   *receiver_line_index_start,
               int   *receiver_line_index_incre,
               int   *receiver_line_count,
               char **receiver_line_name)
{
  int ierr = 0;

  // init
  ioline->num_of_lines  = 0;
  ioline->max_nt        = nt_total;
  ioline->ncmp          = num_of_vars;

  // alloc as max num to keep nr and seq values, easy for second round
  ioline->line_nr  = (int *) malloc(number_of_receiver_line * sizeof(int));
  ioline->line_seq = (int *) malloc(number_of_receiver_line * sizeof(int));

  // first run to count line and nr
  for (int n=0; n < number_of_receiver_line; n++)
  {
    int nr = 0;
    for (int ipt=0; ipt<receiver_line_count[n]; ipt++)
    {
      int gi = receiver_line_index_start[n*CONST_NDIM+0] 
                 + ipt * receiver_line_index_incre[n*CONST_NDIM  ];
      int gj = receiver_line_index_start[n*CONST_NDIM+1] 
                 + ipt * receiver_line_index_incre[n*CONST_NDIM+1];
      int gk = receiver_line_index_start[n*CONST_NDIM+2] 
                 + ipt * receiver_line_index_incre[n*CONST_NDIM+2];

      if (gd_info_gindx_is_inner(gi,gj,gk,gd) == 1)
      {
        nr += 1;
      }
    }

    // if any receiver of this line in this thread
    if (nr>0)
    {
      ioline->line_nr [ ioline->num_of_lines ] = nr;
      ioline->line_seq[ ioline->num_of_lines ] = n;
      ioline->num_of_lines += 1;
    }
  }

  // alloc
  if (ioline->num_of_lines>0)
  {
    ioline->line_name   = (char **)fdlib_mem_malloc_2l_char(ioline->num_of_lines,
                                    CONST_MAX_STRLEN, "io_line_locate");

    ioline->recv_seq    = (int **) malloc(ioline->num_of_lines * sizeof(int*));
    //ioline->recv_indx   = (int **) malloc(ioline->num_of_lines * sizeof(int*));
    ioline->recv_iptr   = (int **) malloc(ioline->num_of_lines * sizeof(int*));
    ioline->recv_x  = (float **) malloc(ioline->num_of_lines * sizeof(float*));
    ioline->recv_y  = (float **) malloc(ioline->num_of_lines * sizeof(float*));
    ioline->recv_z  = (float **) malloc(ioline->num_of_lines * sizeof(float*));
    ioline->recv_seismo = (float **) malloc(ioline->num_of_lines * sizeof(float*));

    for (int n=0; n < ioline->num_of_lines; n++)
    {
      int nr = ioline->line_nr[n];
      //ioline->recv_indx[n] = (int *)malloc(nr * CONST_NDIM * sizeof(int)); 
      ioline->recv_seq [n]  = (int *)malloc( nr * sizeof(int) ); 
      ioline->recv_iptr[n]  = (int *)malloc( nr * sizeof(int) ); 
      ioline->recv_x[n] = (float *)malloc( nr * sizeof(float) );
      ioline->recv_y[n] = (float *)malloc( nr * sizeof(float) );
      ioline->recv_z[n] = (float *)malloc( nr * sizeof(float) );
      ioline->recv_seismo[n] = (float *)malloc(
                                nr * num_of_vars * nt_total * sizeof(float) );
    }
  }

  // second run for value
  //  only loop lines in this thread
  for (int m=0; m < ioline->num_of_lines; m++)
  {
    int n = ioline->line_seq[m];

    sprintf(ioline->line_name[m], "%s", receiver_line_name[n]);

    int ir = 0;
    for (int ipt=0; ipt<receiver_line_count[n]; ipt++)
    {
      int gi = receiver_line_index_start[n*CONST_NDIM+0] + ipt * receiver_line_index_incre[n*CONST_NDIM  ];
      int gj = receiver_line_index_start[n*CONST_NDIM+1] + ipt * receiver_line_index_incre[n*CONST_NDIM+1];
      int gk = receiver_line_index_start[n*CONST_NDIM+2] + ipt * receiver_line_index_incre[n*CONST_NDIM+2];

      if (gd_info_gindx_is_inner(gi,gj,gk,gd) == 1)
      {
        int i = gd_info_indx_glphy2lcext_i(gi,gd);
        int j = gd_info_indx_glphy2lcext_j(gj,gd);
        int k = gd_info_indx_glphy2lcext_k(gk,gd);

        int iptr = i + j * gd->siz_iy + k * gd->siz_iz;

        ioline->recv_seq [m][ir] = ipt;
        ioline->recv_iptr[m][ir] = iptr;

        ioline->recv_x[m][ir] = gd_coord_get_x(gd,i,j,k);
        ioline->recv_y[m][ir] = gd_coord_get_y(gd,i,j,k);
        ioline->recv_z[m][ir] = gd_coord_get_z(gd,i,j,k);

        ir += 1;
      }
    }
  }

  return ierr;
}

int
io_recv_keep(iorecv_t *iorecv, float *w_pre_d, 
             float *buff, int it, int ncmp, size_t siz_icmp)
{
  float Lx1, Lx2, Ly1, Ly2, Lz1, Lz2;
  //CONST_2_NDIM = 8, use 8 points interp
  int size = sizeof(float)*ncmp*CONST_2_NDIM;
  float *buff_d = (float *) cuda_malloc(size);
  size_t *indx1d_d = (size_t *) cuda_malloc(sizeof(size_t)*CONST_2_NDIM);
  dim3 block(32);
  dim3 grid;
  grid.x = (ncmp+block.x-1)/block.x;
  for (int n=0; n < iorecv->total_number; n++)
  {
    iorecv_one_t *this_recv = iorecv->recvone + n;
    size_t *indx1d = this_recv->indx1d;
    CUDACHECK(cudaMemcpy(indx1d_d,indx1d,sizeof(size_t)*CONST_2_NDIM,cudaMemcpyHostToDevice));

    // get coef of linear interp
    Lx2 = this_recv->di; Lx1 = 1.0 - Lx2;
    Ly2 = this_recv->dj; Ly1 = 1.0 - Ly2;
    Lz2 = this_recv->dk; Lz1 = 1.0 - Lz2;

    io_recv_line_interp_pack_buff<<<grid, block>>> (w_pre_d, buff_d, ncmp, siz_icmp, indx1d_d);
    CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));
    for (int icmp=0; icmp < ncmp; icmp++)
    {
      int iptr_sta = icmp * iorecv->max_nt + it;
      this_recv->seismo[iptr_sta] =  buff[CONST_2_NDIM*icmp + 0] * Lx1 * Ly1 * Lz1
                                   + buff[CONST_2_NDIM*icmp + 1] * Lx2 * Ly1 * Lz1
                                   + buff[CONST_2_NDIM*icmp + 2] * Lx1 * Ly2 * Lz1
                                   + buff[CONST_2_NDIM*icmp + 3] * Lx2 * Ly2 * Lz1
                                   + buff[CONST_2_NDIM*icmp + 5] * Lx1 * Ly1 * Lz2
                                   + buff[CONST_2_NDIM*icmp + 5] * Lx2 * Ly1 * Lz2
                                   + buff[CONST_2_NDIM*icmp + 6] * Lx1 * Ly2 * Lz2
                                   + buff[CONST_2_NDIM*icmp + 7] * Lx2 * Ly2 * Lz2;
    }
  }
  CUDACHECK(cudaFree(buff_d));
  CUDACHECK(cudaFree(indx1d_d));

  return 0;
}

int
io_line_keep(ioline_t *ioline, float *w_pre_d,
             float *buff, int it, int ncmp, size_t siz_icmp)
{
  int size = sizeof(float)*ncmp;
  float *buff_d = (float *) cuda_malloc(size);
  dim3 block(32);
  dim3 grid;
  grid.x = (ncmp+block.x-1)/block.x;
  for (int n=0; n < ioline->num_of_lines; n++)
  {
    int   *this_line_iptr   = ioline->recv_iptr[n];
    float *this_line_seismo = ioline->recv_seismo[n];
  
    for (int ir=0; ir < ioline->line_nr[n]; ir++)
    {
      int iptr = this_line_iptr[ir];
      float *this_seismo = this_line_seismo + ir * ioline->max_nt * ncmp;
      io_recv_line_pack_buff<<<grid, block>>>(w_pre_d, buff_d, ncmp, siz_icmp, iptr);
      CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));
      for (int icmp=0; icmp < ncmp; icmp++)
      {
        int iptr_seismo = icmp * ioline->max_nt + it;
        this_seismo[iptr_seismo] = buff[icmp];
      }
    }
  }
  CUDACHECK(cudaFree(buff_d));

  return 0;
}

__global__ void
recv_depth_to_axis(float *all_coords_d, int num_recv, gd_t gd_d, 
                   int *flag_indx, int *flag_depth, MPI_Comm comm, int myid)
{
  size_t ix = blockIdx.x * blockDim.x + threadIdx.x;  
  if(ix<num_recv)
  {
    float sx = all_coords_d[3*ix+0];
    float sy = all_coords_d[3*ix+1];
    if(flag_indx[ix] == 0 && flag_depth[ix] == 1)
    {
      gd_curv_depth_to_axis(&gd_d,sx,sy,&all_coords_d[3*ix+2],comm,myid);
    }
  }
}

__global__ void 
recv_coords_to_glob_indx(float *all_coords_d, int *all_index_d, 
                         float *all_inc_d, int num_recv, gd_t gd_d, 
                         int *flag_indx, MPI_Comm comm, int myid)
{
  int ix = blockIdx.x * blockDim.x + threadIdx.x;
  if(ix < num_recv)
  {
    // count num of recv in this thread
    // convert coord to glob index
    int ri_glob, rj_glob, rk_glob;
    float rx_inc,ry_inc,rz_inc;
    float sx = all_coords_d[3*ix+0];
    float sy = all_coords_d[3*ix+1];
    float sz = all_coords_d[3*ix+2];
    if(flag_indx[ix] == 0)
    {

      gd_curv_coord_to_glob_indx_gpu(&gd_d,sx,sy,sz,comm,myid,&ri_glob, &rj_glob, &rk_glob, &rx_inc,&ry_inc,&rz_inc);
      // keep index to avoid duplicat run
      all_index_d[3*ix+0] = ri_glob;
      all_index_d[3*ix+1] = rj_glob;
      all_index_d[3*ix+2] = rk_glob;
      all_inc_d[3*ix+0]   = rx_inc;
      all_inc_d[3*ix+1]   = ry_inc;
      all_inc_d[3*ix+2]   = rz_inc;
    }
  }
}

__global__ void
io_recv_line_interp_pack_buff(float *var, float *buff_d, int ncmp, size_t siz_icmp, size_t *indx1d_d)
{
  size_t ix = blockIdx.x * blockDim.x + threadIdx.x;
  //indx1d_d size is CONST_2_NDIM = 8
  if(ix < ncmp)
  {
   buff_d[8*ix+0] = var[ix*siz_icmp + indx1d_d[0] ];
   buff_d[8*ix+1] = var[ix*siz_icmp + indx1d_d[1] ];
   buff_d[8*ix+2] = var[ix*siz_icmp + indx1d_d[2] ];
   buff_d[8*ix+3] = var[ix*siz_icmp + indx1d_d[3] ];
   buff_d[8*ix+4] = var[ix*siz_icmp + indx1d_d[4] ];
   buff_d[8*ix+5] = var[ix*siz_icmp + indx1d_d[5] ];
   buff_d[8*ix+6] = var[ix*siz_icmp + indx1d_d[6] ];
   buff_d[8*ix+7] = var[ix*siz_icmp + indx1d_d[7] ];
  }
}

__global__ void
io_recv_line_pack_buff(float *var, float *buff_d, int ncmp, size_t siz_icmp, int iptr)
{
  size_t ix = blockIdx.x * blockDim.x + threadIdx.x;
  if(ix < ncmp)
  {
   buff_d[ix] = var[ix*siz_icmp + iptr];
  }
}

int
io_recv_output_sac(iorecv_t *iorecv,
                   float dt,
                   int num_of_vars,
                   char **cmp_name,
                   char *output_dir,
                   char *err_message)
{
  // use fake evt_x etc. since did not implement gather evt_x by mpi
  float evt_x = 0.0;
  float evt_y = 0.0;
  float evt_z = 0.0;
  float evt_d = 0.0;
  char ou_file[CONST_MAX_STRLEN];

  for (int ir=0; ir < iorecv->total_number; ir++)
  {
    iorecv_one_t *this_recv = iorecv->recvone + ir;

    //fprintf(stdout,"=== Debug: num_of_vars=%d\n",num_of_vars);fflush(stdout);
    for (int icmp=0; icmp < num_of_vars; icmp++)
    {
      //fprintf(stdout,"=== Debug: icmp=%d\n",icmp);fflush(stdout);

      float *this_trace = this_recv->seismo + icmp * iorecv->max_nt;

      sprintf(ou_file,"%s/%s.%s.sac", output_dir, 
                      this_recv->name, cmp_name[icmp]);

      //fprintf(stdout,"=== Debug: icmp=%d,ou_file=%s\n",icmp,ou_file);fflush(stdout);

      sacExport1C1R(ou_file,
            this_trace,
            evt_x, evt_y, evt_z, evt_d,
            this_recv->x, this_recv->y, this_recv->z,
            dt, dt, iorecv->max_nt, err_message);
    }
  }

  return 0;
}

// calculate and output strain cmp for elastic medium
//   do not find a better file to hold this func
//   temporarily put here

int
io_recv_output_sac_el_iso_strain(iorecv_t *iorecv,
                     float *lam3d,
                     float *mu3d,
                     float dt,
                     char *output_dir,
                     char *err_message)
{
  // use fake evt_x etc. since did not implement gather evt_x by mpi
  float evt_x = 0.0;
  float evt_y = 0.0;
  float evt_z = 0.0;
  float evt_d = 0.0;
  char ou_file[CONST_MAX_STRLEN];

  for (int ir=0; ir < iorecv->total_number; ir++)
  {
    iorecv_one_t *this_recv = iorecv->recvone + ir;
    size_t iptr = this_recv->indx1d[0];

    float lam = lam3d[iptr];
    float mu  =  mu3d[iptr];

    // cmp seq hard-coded, need to revise in the future
    float *Txx = this_recv->seismo + 3 * iorecv->max_nt;
    float *Tyy = this_recv->seismo + 4 * iorecv->max_nt;
    float *Tzz = this_recv->seismo + 5 * iorecv->max_nt;
    float *Tyz = this_recv->seismo + 6 * iorecv->max_nt;
    float *Txz = this_recv->seismo + 7 * iorecv->max_nt;
    float *Txy = this_recv->seismo + 8 * iorecv->max_nt;

    float E1 = (lam + mu) / (mu * ( 3.0 * lam + 2.0 * mu));
    float E2 = - lam / ( 2.0 * mu * (3.0 * lam + 2.0 * mu));
    float E3 = 1.0 / mu;

    // conver to strain per time step
    for (int it = 0; it < iorecv->max_nt; it++)
    {
      float E0 = E2 * (Txx[it] + Tyy[it] + Tzz[it]);

      Txx[it] = E0 - (E2 - E1) * Txx[it];
      Tyy[it] = E0 - (E2 - E1) * Tyy[it];
      Tzz[it] = E0 - (E2 - E1) * Tzz[it];
      Tyz[it] = 0.5 * E3 * Tyz[it];
      Txz[it] = 0.5 * E3 * Txz[it];
      Txy[it] = 0.5 * E3 * Txy[it];
    }

    // output to sca file
    sprintf(ou_file,"%s/%s.%s.sac", output_dir, this_recv->name, "Exx");
    sacExport1C1R(ou_file,Txx,evt_x, evt_y, evt_z, evt_d,
          this_recv->x, this_recv->y, this_recv->z,
          dt, dt, iorecv->max_nt, err_message);

    sprintf(ou_file,"%s/%s.%s.sac", output_dir, this_recv->name, "Eyy");
    sacExport1C1R(ou_file,Tyy,evt_x, evt_y, evt_z, evt_d,
          this_recv->x, this_recv->y, this_recv->z,
          dt, dt, iorecv->max_nt, err_message);

    sprintf(ou_file,"%s/%s.%s.sac", output_dir, this_recv->name, "Ezz");
    sacExport1C1R(ou_file,Tzz,evt_x, evt_y, evt_z, evt_d,
          this_recv->x, this_recv->y, this_recv->z,
          dt, dt, iorecv->max_nt, err_message);

    sprintf(ou_file,"%s/%s.%s.sac", output_dir, this_recv->name, "Eyz");
    sacExport1C1R(ou_file,Tyz,evt_x, evt_y, evt_z, evt_d,
          this_recv->x, this_recv->y, this_recv->z,
          dt, dt, iorecv->max_nt, err_message);

    sprintf(ou_file,"%s/%s.%s.sac", output_dir, this_recv->name, "Exz");
    sacExport1C1R(ou_file,Txz,evt_x, evt_y, evt_z, evt_d,
          this_recv->x, this_recv->y, this_recv->z,
          dt, dt, iorecv->max_nt, err_message);

    sprintf(ou_file,"%s/%s.%s.sac", output_dir, this_recv->name, "Exy");
    sacExport1C1R(ou_file,Txy,evt_x, evt_y, evt_z, evt_d,
          this_recv->x, this_recv->y, this_recv->z,
          dt, dt, iorecv->max_nt, err_message);
  } // loop ir

  return 0;
}

int
io_recv_output_sac_el_vti_strain(iorecv_t *iorecv,
                        float * c11, float * c13,
                        float * c33, float * c55,
                        float * c66,
                        float dt,
                        char *evtnm,
                        char *output_dir,
                        char *err_message)
{
  //not implement



  return 0;
}
int
io_recv_output_sac_el_aniso_strain(iorecv_t *iorecv,
                        float * c11, float * c12,
                        float * c13, float * c14,
                        float * c15, float * c16,
                        float * c22, float * c23,
                        float * c24, float * c25,
                        float * c26, float * c33,
                        float * c34, float * c35,
                        float * c36, float * c44,
                        float * c45, float * c46,
                        float * c55, float * c56,
                        float * c66,
                        float dt,
                        char *evtnm,
                        char *output_dir,
                        char *err_message)
{
  //not implement



  return 0;
}
int
io_line_output_sac(ioline_t *ioline,
      float dt, char **cmp_name, char *output_dir)
{
  // use fake evt_x etc. since did not implement gather evt_x by mpi
  float evt_x = 0.0;
  float evt_y = 0.0;
  float evt_z = 0.0;
  float evt_d = 0.0;
  char ou_file[CONST_MAX_STRLEN];
  char err_message[CONST_MAX_STRLEN];
  
  for (int n=0; n < ioline->num_of_lines; n++)
  {
    int   *this_line_iptr   = ioline->recv_iptr[n];
    float *this_line_seismo = ioline->recv_seismo[n];

    for (int ir=0; ir < ioline->line_nr[n]; ir++)
    {
      float *this_seismo = this_line_seismo + ir * ioline->max_nt * ioline->ncmp;

      for (int icmp=0; icmp < ioline->ncmp; icmp++)
      {
        float *this_trace = this_seismo + icmp * ioline->max_nt;

        sprintf(ou_file,"%s/%s.no%d.%s.sac", output_dir,
                  ioline->line_name[n],ioline->recv_seq[n][ir],
                  cmp_name[icmp]);

        sacExport1C1R(ou_file,
              this_trace,
              evt_x, evt_y, evt_z, evt_d,
              ioline->recv_x[n][ir],
              ioline->recv_y[n][ir],
              ioline->recv_z[n][ir],
              dt, dt, ioline->max_nt, err_message);
      } // icmp
    } // ir
  } // line

  return 0;
}


int
io_slice_locate(gd_t  *gd,
                ioslice_t *ioslice,
                int  number_of_slice_x,
                int  number_of_slice_y,
                int  number_of_slice_z,
                int *slice_x_index,
                int *slice_y_index,
                int *slice_z_index,
                char *output_fname_part,
                char *output_dir)
{
  int ierr = 0;

  ioslice->siz_max_wrk = 0;

  if (number_of_slice_x>0) {
    ioslice->slice_x_fname = (char **) fdlib_mem_malloc_2l_char(number_of_slice_x,
                                                            CONST_MAX_STRLEN,
                                                            "slice_x_fname");
    ioslice->slice_x_indx = (int *) malloc(number_of_slice_x * sizeof(int));
  }
  if (number_of_slice_y>0) {
    ioslice->slice_y_fname = (char **) fdlib_mem_malloc_2l_char(number_of_slice_y,
                                                            CONST_MAX_STRLEN,
                                                            "slice_y_fname");
    ioslice->slice_y_indx = (int *) malloc(number_of_slice_y * sizeof(int));
  }
  if (number_of_slice_z>0) {
    ioslice->slice_z_fname = (char **) fdlib_mem_malloc_2l_char(number_of_slice_z,
                                                            CONST_MAX_STRLEN,
                                                            "slice_z_fname");
    ioslice->slice_z_indx = (int *) malloc(number_of_slice_z * sizeof(int));
  }

  // init
  ioslice->num_of_slice_x = 0;
  ioslice->num_of_slice_y = 0;
  ioslice->num_of_slice_z = 0;

  // x slice
  for (int n=0; n < number_of_slice_x; n++)
  {
    int gi = slice_x_index[n];
    // output slice file add 1, not start from 0.
    int gi_1 = gi+1;
    if (gd_info_gindx_is_inner_i(gi, gd)==1)
    {
      int islc = ioslice->num_of_slice_x;

      ioslice->slice_x_indx[islc]  = gd_info_indx_glphy2lcext_i(gi, gd);
      sprintf(ioslice->slice_x_fname[islc],"%s/slicex_i%d_%s.nc",
                output_dir,gi_1,output_fname_part);

      ioslice->num_of_slice_x += 1;

      size_t slice_siz = gd->nj * gd->nk;
      ioslice->siz_max_wrk = slice_siz > ioslice->siz_max_wrk ? 
                             slice_siz : ioslice->siz_max_wrk;
    }
  }

  // y slice
  for (int n=0; n < number_of_slice_y; n++)
  {
    int gj = slice_y_index[n];
    // output slice file add 1, not start from 0.
    int gj_1 = gj+1;
    if (gd_info_gindx_is_inner_j(gj, gd)==1)
    {
      int islc = ioslice->num_of_slice_y;

      ioslice->slice_y_indx[islc]  = gd_info_indx_glphy2lcext_j(gj, gd);
      sprintf(ioslice->slice_y_fname[islc],"%s/slicey_j%d_%s.nc",
                output_dir,gj_1,output_fname_part);

      ioslice->num_of_slice_y += 1;

      size_t slice_siz = gd->ni * gd->nk;
      ioslice->siz_max_wrk = slice_siz > ioslice->siz_max_wrk ? 
                             slice_siz : ioslice->siz_max_wrk;
    }
  }

  // z slice
  for (int n=0; n < number_of_slice_z; n++)
  {
    int gk = slice_z_index[n];
    // output slice file add 1, not start from 0.
    int gk_1 = gk+1;
    if (gd_info_gindx_is_inner_k(gk, gd)==1)
    {
      int islc = ioslice->num_of_slice_z;

      ioslice->slice_z_indx[islc]  = gd_info_indx_glphy2lcext_k(gk, gd);
      sprintf(ioslice->slice_z_fname[islc],"%s/slicez_k%d_%s.nc",
                output_dir,gk_1,output_fname_part);

      ioslice->num_of_slice_z += 1;

      size_t slice_siz = gd->ni * gd->nj;
      ioslice->siz_max_wrk = slice_siz > ioslice->siz_max_wrk ? 
                             slice_siz : ioslice->siz_max_wrk;
    }
  }

  return ierr;
}

int
io_slice_nc_create(ioslice_t *ioslice, 
                  int num_of_vars, char **w3d_name,
                  int ni, int nj, int nk,
                  int *topoid, ioslice_nc_t *ioslice_nc)
{
  int ierr = 0;

  int num_of_slice_x = ioslice->num_of_slice_x;
  int num_of_slice_y = ioslice->num_of_slice_y;
  int num_of_slice_z = ioslice->num_of_slice_z;

  ioslice_nc->num_of_slice_x = num_of_slice_x;
  ioslice_nc->num_of_slice_y = num_of_slice_y;
  ioslice_nc->num_of_slice_z = num_of_slice_z;
  ioslice_nc->num_of_vars    = num_of_vars   ;

  // malloc vars
  ioslice_nc->ncid_slx = (int *)malloc(num_of_slice_x*sizeof(int));
  ioslice_nc->ncid_sly = (int *)malloc(num_of_slice_y*sizeof(int));
  ioslice_nc->ncid_slz = (int *)malloc(num_of_slice_z*sizeof(int));

  ioslice_nc->timeid_slx = (int *)malloc(num_of_slice_x*sizeof(int));
  ioslice_nc->timeid_sly = (int *)malloc(num_of_slice_y*sizeof(int));
  ioslice_nc->timeid_slz = (int *)malloc(num_of_slice_z*sizeof(int));

  ioslice_nc->varid_slx = (int *)malloc(num_of_vars*num_of_slice_x*sizeof(int));
  ioslice_nc->varid_sly = (int *)malloc(num_of_vars*num_of_slice_y*sizeof(int));
  ioslice_nc->varid_slz = (int *)malloc(num_of_vars*num_of_slice_z*sizeof(int));

  // slice x
  for (int n=0; n<num_of_slice_x; n++)
  {
    int dimid[3];
    ierr = nc_create(ioslice->slice_x_fname[n], NC_CLOBBER,
                  &(ioslice_nc->ncid_slx[n])); 
    handle_nc_err(ierr);
    ierr = nc_def_dim(ioslice_nc->ncid_slx[n], "time", NC_UNLIMITED, &dimid[0]); handle_nc_err(ierr);
    ierr = nc_def_dim(ioslice_nc->ncid_slx[n], "k"   , nk          , &dimid[1]); handle_nc_err(ierr);
    ierr = nc_def_dim(ioslice_nc->ncid_slx[n], "j"   , nj          , &dimid[2]); handle_nc_err(ierr);
    // time var
    ierr = nc_def_var(ioslice_nc->ncid_slx[n], "time", NC_FLOAT, 1, dimid+0,
                   &(ioslice_nc->timeid_slx[n]));
    handle_nc_err(ierr);
    // other vars
    for (int ivar=0; ivar<num_of_vars; ivar++) {
      ierr = nc_def_var(ioslice_nc->ncid_slx[n], w3d_name[ivar], NC_FLOAT, 3, dimid,
                     &(ioslice_nc->varid_slx[ivar+n*num_of_vars])); handle_nc_err(ierr);
    }
    // attribute: index info for plot
    nc_put_att_int(ioslice_nc->ncid_slx[n],NC_GLOBAL,"i_index_with_ghosts_in_this_thread",
                   NC_INT,1,ioslice->slice_x_indx+n);
    nc_put_att_int(ioslice_nc->ncid_slx[n],NC_GLOBAL,"coords_of_mpi_topo",
                   NC_INT,3,topoid);
    // end def
    ierr = nc_enddef(ioslice_nc->ncid_slx[n]); handle_nc_err(ierr);
  }

  // slice y
  for (int n=0; n<num_of_slice_y; n++)
  {
    int dimid[3];
    ierr = nc_create(ioslice->slice_y_fname[n], NC_CLOBBER,
                  &(ioslice_nc->ncid_sly[n])); handle_nc_err(ierr);
    ierr = nc_def_dim(ioslice_nc->ncid_sly[n], "time", NC_UNLIMITED, &dimid[0]); handle_nc_err(ierr);
    ierr = nc_def_dim(ioslice_nc->ncid_sly[n], "k"   , nk          , &dimid[1]); handle_nc_err(ierr);
    ierr = nc_def_dim(ioslice_nc->ncid_sly[n], "i"   , ni          , &dimid[2]); handle_nc_err(ierr);
    // time var
    ierr = nc_def_var(ioslice_nc->ncid_sly[n], "time", NC_FLOAT, 1, dimid+0,
                   &(ioslice_nc->timeid_sly[n])); handle_nc_err(ierr);
    // other vars
    for (int ivar=0; ivar<num_of_vars; ivar++) {
      ierr = nc_def_var(ioslice_nc->ncid_sly[n], w3d_name[ivar], NC_FLOAT, 3, dimid,
                     &(ioslice_nc->varid_sly[ivar+n*num_of_vars])); handle_nc_err(ierr);
    }
    // attribute: index info for plot
    nc_put_att_int(ioslice_nc->ncid_sly[n],NC_GLOBAL,"j_index_with_ghosts_in_this_thread",
                   NC_INT,1,ioslice->slice_y_indx+n);
    nc_put_att_int(ioslice_nc->ncid_sly[n],NC_GLOBAL,"coords_of_mpi_topo",
                   NC_INT,3,topoid);
    // end def
    ierr = nc_enddef(ioslice_nc->ncid_sly[n]); handle_nc_err(ierr);
  }

  // slice z
  for (int n=0; n<num_of_slice_z; n++)
  {
    int dimid[3];
    ierr = nc_create(ioslice->slice_z_fname[n], NC_CLOBBER,
                  &(ioslice_nc->ncid_slz[n])); handle_nc_err(ierr);
    ierr = nc_def_dim(ioslice_nc->ncid_slz[n], "time", NC_UNLIMITED, &dimid[0]); handle_nc_err(ierr);
    ierr = nc_def_dim(ioslice_nc->ncid_slz[n], "j"   , nj          , &dimid[1]); handle_nc_err(ierr);
    ierr = nc_def_dim(ioslice_nc->ncid_slz[n], "i"   , ni          , &dimid[2]); handle_nc_err(ierr);
    // time var
    ierr = nc_def_var(ioslice_nc->ncid_slz[n], "time", NC_FLOAT, 1, dimid+0,
                   &(ioslice_nc->timeid_slz[n])); handle_nc_err(ierr);
    // other vars
    for (int ivar=0; ivar<num_of_vars; ivar++) {
      ierr = nc_def_var(ioslice_nc->ncid_slz[n], w3d_name[ivar], NC_FLOAT, 3, dimid,
                     &(ioslice_nc->varid_slz[ivar+n*num_of_vars])); handle_nc_err(ierr);
    }
    // attribute: index info for plot
    nc_put_att_int(ioslice_nc->ncid_slz[n],NC_GLOBAL,"k_index_with_ghosts_in_this_thread",
                   NC_INT,1,ioslice->slice_z_indx+n);
    nc_put_att_int(ioslice_nc->ncid_slz[n],NC_GLOBAL,"coords_of_mpi_topo",
                   NC_INT,3,topoid);
    // end def
    ierr = nc_enddef(ioslice_nc->ncid_slz[n]); handle_nc_err(ierr);
  }

  return ierr;
}

int
io_slice_nc_put(ioslice_t    *ioslice,
                ioslice_nc_t *ioslice_nc,
                gd_t     *gd,
                float *w_pre_d,
                float *buff,
                int   it,
                float time)
{
  int ierr = 0;

  int ni1 = gd->ni1;
  int ni2 = gd->ni2;
  int nj1 = gd->nj1;
  int nj2 = gd->nj2;
  int nk1 = gd->nk1;
  int nk2 = gd->nk2;
  int ni  = gd->ni ;
  int nj  = gd->nj ;
  int nk  = gd->nk ;
  size_t siz_iy = gd->siz_iy;
  size_t siz_iz = gd->siz_iz;
  size_t siz_icmp = gd->siz_icmp;

  int  num_of_vars = ioslice_nc->num_of_vars;

  //-- slice x, 
  for (int n=0; n < ioslice_nc->num_of_slice_x; n++)
  {
    size_t startp[] = { it, 0, 0 };
    size_t countp[] = { 1, nk, nj};
    size_t start_tdim = it;

    nc_put_var1_float(ioslice_nc->ncid_slx[n], ioslice_nc->timeid_slx[n],
                        &start_tdim, &time);

    int i = ioslice->slice_x_indx[n];
    size_t size = sizeof(float) * nj * nk; 
    float *buff_d;
    buff_d = (float *) cuda_malloc(size);
    dim3 block(8,8);
    dim3 grid;
    grid.x = (nj+block.x-1)/block.x;
    grid.y = (nk+block.y-1)/block.y;
    for (int ivar=0; ivar<num_of_vars; ivar++)
    {
      float *var = w_pre_d + ivar * siz_icmp;
      io_slice_pack_buff_x<<<grid, block>>>(i,nj,nk,siz_iy,siz_iz,var,buff_d);
      CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));

      nc_put_vara_float(ioslice_nc->ncid_slx[n], 
                        ioslice_nc->varid_slx[n*num_of_vars + ivar],
                        startp, countp, buff);
    }
    CUDACHECK(cudaFree(buff_d));
  }
  // slice y
  for (int n=0; n < ioslice_nc->num_of_slice_y; n++)
  {
    size_t startp[] = { it, 0, 0 };
    size_t countp[] = { 1, nk, ni};
    size_t start_tdim = it;

    nc_put_var1_float(ioslice_nc->ncid_sly[n], ioslice_nc->timeid_sly[n],
                        &start_tdim, &time);

    int j = ioslice->slice_y_indx[n];
    int size = sizeof(float) * ni * nk; 
    float *buff_d;
    buff_d = (float *) cuda_malloc(size);
    dim3 block(8,8);
    dim3 grid;
    grid.x = (ni+block.x-1)/block.x;
    grid.y = (nk+block.y-1)/block.y;
    for (int ivar=0; ivar<num_of_vars; ivar++)
    {
      float *var = w_pre_d + ivar * siz_icmp;
      io_slice_pack_buff_y<<<grid, block>>>(j,ni,nk,siz_iy,siz_iz,var,buff_d);
      CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));

      nc_put_vara_float(ioslice_nc->ncid_sly[n], 
                        ioslice_nc->varid_sly[n*num_of_vars + ivar],
                        startp, countp, buff);
    }
    CUDACHECK(cudaFree(buff_d));
  }

  // slice z
  for (int n=0; n < ioslice_nc->num_of_slice_z; n++)
  {
    size_t startp[] = { it, 0, 0 };
    size_t countp[] = { 1, nj, ni};
    size_t start_tdim = it;

    nc_put_var1_float(ioslice_nc->ncid_slz[n], ioslice_nc->timeid_slz[n],
                        &start_tdim, &time);

    int k = ioslice->slice_z_indx[n];
    int size = sizeof(float) * ni * nj; 
    float *buff_d;
    buff_d = (float *) cuda_malloc(size);
    dim3 block(8,8);
    dim3 grid;
    grid.x = (ni+block.x-1)/block.x;
    grid.y = (nj+block.y-1)/block.y;
    for (int ivar=0; ivar<num_of_vars; ivar++)
    {
      float *var = w_pre_d + ivar * siz_icmp;
      io_slice_pack_buff_z<<<grid, block>>>(k,ni,nj,siz_iy,siz_iz,var,buff_d);
      CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));

      nc_put_vara_float(ioslice_nc->ncid_slz[n], 
                          ioslice_nc->varid_slz[n*num_of_vars + ivar],
                          startp, countp, buff);
    }
    CUDACHECK(cudaFree(buff_d));
  }

  return ierr;
}

int
io_snapshot_locate(gd_t *gd,
                   iosnap_t *iosnap,
                    int  number_of_snapshot,
                    char **snapshot_name,
                    int *snapshot_index_start,
                    int *snapshot_index_count,
                    int *snapshot_index_incre,
                    int *snapshot_time_start,
                    int *snapshot_time_incre,
                    int *snapshot_save_velocity,
                    int *snapshot_save_stress,
                    int *snapshot_save_strain,
                    char *output_fname_part,
                    char *output_dir)
{
  // malloc to max, num of snap will not be large
  if (number_of_snapshot > 0)
  {
    iosnap->fname = (char **) fdlib_mem_malloc_2l_char(number_of_snapshot,
                                    CONST_MAX_STRLEN,"snap_fname");
    iosnap->i1 = (int *) malloc(number_of_snapshot * sizeof(int));
    iosnap->j1 = (int *) malloc(number_of_snapshot * sizeof(int));
    iosnap->k1 = (int *) malloc(number_of_snapshot * sizeof(int));
    iosnap->ni = (int *) malloc(number_of_snapshot * sizeof(int));
    iosnap->nj = (int *) malloc(number_of_snapshot * sizeof(int));
    iosnap->nk = (int *) malloc(number_of_snapshot * sizeof(int));
    iosnap->di = (int *) malloc(number_of_snapshot * sizeof(int));
    iosnap->dj = (int *) malloc(number_of_snapshot * sizeof(int));
    iosnap->dk = (int *) malloc(number_of_snapshot * sizeof(int));
    iosnap->it1 = (int *) malloc(number_of_snapshot * sizeof(int));
    iosnap->dit = (int *) malloc(number_of_snapshot * sizeof(int));
    iosnap->out_vel    = (int *) malloc(number_of_snapshot * sizeof(int));
    iosnap->out_stress = (int *) malloc(number_of_snapshot * sizeof(int));
    iosnap->out_strain = (int *) malloc(number_of_snapshot * sizeof(int));

    iosnap->i1_to_glob = (int *) malloc(number_of_snapshot * sizeof(int));
    iosnap->j1_to_glob = (int *) malloc(number_of_snapshot * sizeof(int));
    iosnap->k1_to_glob = (int *) malloc(number_of_snapshot * sizeof(int));
  }

  // init

  iosnap->siz_max_wrk = 0;

  int isnap = 0;

  for (int n=0; n < number_of_snapshot; n++)
  {
    int iptr0 = n*CONST_NDIM;

    // scan output k-index in this proc
    int gk1 = -1; int ngk =  0; int k_in_nc = 0;
    for (int n3=0; n3<snapshot_index_count[iptr0+2]; n3++)
    {
      int gk = snapshot_index_start[iptr0+2] + n3 * snapshot_index_incre[iptr0+2];
      if (gd_info_gindx_is_inner_k(gk,gd) == 1)
      {
        if (gk1 == -1) {
          gk1 = gk;
          k_in_nc = n3;
        }
        ngk++;
      }
      if (gk > gd->gnk2) break; // no need to larger k
    }

    // scan output j-index in this proc
    int gj1 = -1; int ngj =  0; int j_in_nc = 0;
    for (int n2=0; n2<snapshot_index_count[iptr0+1]; n2++)
    {
      int gj = snapshot_index_start[iptr0+1] + n2 * snapshot_index_incre[iptr0+1];
      if (gd_info_gindx_is_inner_j(gj,gd) == 1)
      {
        if (gj1 == -1) {
          gj1 = gj;
          j_in_nc = n2;
        }
        ngj++;
      }
      if (gj > gd->gnj2) break;
    }

    // scan output i-index in this proc
    int gi1 = -1; int ngi =  0; int i_in_nc = 0;
    for (int n1=0; n1<snapshot_index_count[iptr0+0]; n1++)
    {
      int gi = snapshot_index_start[iptr0+0] + n1 * snapshot_index_incre[iptr0+0];
      if (gd_info_gindx_is_inner_i(gi,gd) == 1)
      {
        if (gi1 == -1) {
          gi1 = gi;
          i_in_nc = n1;
        }
        ngi++;
      }
      if (gi > gd->gni2) break;
    }

    // if in this proc
    if (ngi>0 && ngj>0 && ngk>0)
    {
      iosnap->i1[isnap]  = gd_info_indx_glphy2lcext_i(gi1, gd);
      iosnap->j1[isnap]  = gd_info_indx_glphy2lcext_j(gj1, gd);
      iosnap->k1[isnap]  = gd_info_indx_glphy2lcext_k(gk1, gd);
      iosnap->ni[isnap]  = ngi;
      iosnap->nj[isnap]  = ngj;
      iosnap->nk[isnap]  = ngk;
      iosnap->di[isnap]  = snapshot_index_incre[iptr0+0];
      iosnap->dj[isnap]  = snapshot_index_incre[iptr0+1];
      iosnap->dk[isnap]  = snapshot_index_incre[iptr0+2];

      iosnap->it1[isnap]  = snapshot_time_start[n];
      iosnap->dit[isnap]  = snapshot_time_incre[n];

      iosnap->out_vel   [isnap] = snapshot_save_velocity[n];
      iosnap->out_stress[isnap] = snapshot_save_stress[n];
      iosnap->out_strain[isnap] = snapshot_save_strain[n];

      iosnap->i1_to_glob[isnap] = i_in_nc;
      iosnap->j1_to_glob[isnap] = j_in_nc;
      iosnap->k1_to_glob[isnap] = k_in_nc;

      sprintf(iosnap->fname[isnap],"%s/%s_%s.nc",output_dir,
                                                 snapshot_name[n],
                                                 output_fname_part);

      // for max wrk
      size_t snap_siz =  ngi * ngj * ngk;
      iosnap->siz_max_wrk = snap_siz > iosnap->siz_max_wrk ? 
                            snap_siz : iosnap->siz_max_wrk;

      isnap += 1;
    } // if in this
  } // loop all snap

  iosnap->num_of_snap = isnap;

  return 0;
}


int
io_snap_nc_create(iosnap_t *iosnap, iosnap_nc_t *iosnap_nc, int *topoid)
{
  int ierr = 0;

  int num_of_snap = iosnap->num_of_snap;
  char **snap_fname = iosnap->fname;

  iosnap_nc->num_of_snap = num_of_snap;
  iosnap_nc->ncid = (int *)malloc(num_of_snap*sizeof(int));
  iosnap_nc->timeid = (int *)malloc(num_of_snap*sizeof(int));

  iosnap_nc->varid_V = (int *)malloc(num_of_snap*CONST_NDIM*sizeof(int));
  iosnap_nc->varid_T = (int *)malloc(num_of_snap*CONST_NDIM_2*sizeof(int));
  iosnap_nc->varid_E = (int *)malloc(num_of_snap*CONST_NDIM_2*sizeof(int));

  // will be used in put step
  iosnap_nc->cur_it = (int *)malloc(num_of_snap*sizeof(int));
  for (int n=0; n<num_of_snap; n++) {
    iosnap_nc->cur_it[n] = 0;
  }

  int *ncid   = iosnap_nc->ncid;
  int *timeid = iosnap_nc->timeid;
  int *varid_V = iosnap_nc->varid_V;
  int *varid_T = iosnap_nc->varid_T;
  int *varid_E = iosnap_nc->varid_E;

  for (int n=0; n<num_of_snap; n++)
  {
    int dimid[4];
    int snap_i1  = iosnap->i1[n];
    int snap_j1  = iosnap->j1[n];
    int snap_k1  = iosnap->k1[n];
    int snap_ni  = iosnap->ni[n];
    int snap_nj  = iosnap->nj[n];
    int snap_nk  = iosnap->nk[n];
    int snap_di  = iosnap->di[n];
    int snap_dj  = iosnap->dj[n];
    int snap_dk  = iosnap->dk[n];

    int snap_out_V = iosnap->out_vel[n];
    int snap_out_T = iosnap->out_stress[n];
    int snap_out_E = iosnap->out_strain[n];

    ierr = nc_create(snap_fname[n], NC_CLOBBER, &ncid[n]);       handle_nc_err(ierr);
    ierr = nc_def_dim(ncid[n], "time", NC_UNLIMITED, &dimid[0]); handle_nc_err(ierr);
    ierr = nc_def_dim(ncid[n], "k", snap_nk     , &dimid[1]);    handle_nc_err(ierr);
    ierr = nc_def_dim(ncid[n], "j", snap_nj     , &dimid[2]);    handle_nc_err(ierr);
    ierr = nc_def_dim(ncid[n], "i", snap_ni     , &dimid[3]);    handle_nc_err(ierr);
    // time var
    ierr = nc_def_var(ncid[n], "time", NC_FLOAT, 1, dimid+0, &timeid[n]); handle_nc_err(ierr);
    // other vars
    if (snap_out_V==1) {
       ierr = nc_def_var(ncid[n],"Vx",NC_FLOAT,4,dimid,&varid_V[n*CONST_NDIM+0]); handle_nc_err(ierr);
       ierr = nc_def_var(ncid[n],"Vy",NC_FLOAT,4,dimid,&varid_V[n*CONST_NDIM+1]); handle_nc_err(ierr);
       ierr = nc_def_var(ncid[n],"Vz",NC_FLOAT,4,dimid,&varid_V[n*CONST_NDIM+2]); handle_nc_err(ierr);
    }
    if (snap_out_T==1) {
       ierr = nc_def_var(ncid[n],"Txx",NC_FLOAT,4,dimid,&varid_T[n*CONST_NDIM_2+0]); handle_nc_err(ierr);
       ierr = nc_def_var(ncid[n],"Tyy",NC_FLOAT,4,dimid,&varid_T[n*CONST_NDIM_2+1]); handle_nc_err(ierr);
       ierr = nc_def_var(ncid[n],"Tzz",NC_FLOAT,4,dimid,&varid_T[n*CONST_NDIM_2+2]); handle_nc_err(ierr);
       ierr = nc_def_var(ncid[n],"Txz",NC_FLOAT,4,dimid,&varid_T[n*CONST_NDIM_2+3]); handle_nc_err(ierr);
       ierr = nc_def_var(ncid[n],"Tyz",NC_FLOAT,4,dimid,&varid_T[n*CONST_NDIM_2+4]); handle_nc_err(ierr);
       ierr = nc_def_var(ncid[n],"Txy",NC_FLOAT,4,dimid,&varid_T[n*CONST_NDIM_2+5]); handle_nc_err(ierr);
    }
    if (snap_out_E==1) {
       ierr = nc_def_var(ncid[n],"Exx",NC_FLOAT,4,dimid,&varid_E[n*CONST_NDIM_2+0]); handle_nc_err(ierr);
       ierr = nc_def_var(ncid[n],"Eyy",NC_FLOAT,4,dimid,&varid_E[n*CONST_NDIM_2+1]); handle_nc_err(ierr);
       ierr = nc_def_var(ncid[n],"Ezz",NC_FLOAT,4,dimid,&varid_E[n*CONST_NDIM_2+2]); handle_nc_err(ierr);
       ierr = nc_def_var(ncid[n],"Exz",NC_FLOAT,4,dimid,&varid_E[n*CONST_NDIM_2+3]); handle_nc_err(ierr);
       ierr = nc_def_var(ncid[n],"Eyz",NC_FLOAT,4,dimid,&varid_E[n*CONST_NDIM_2+4]); handle_nc_err(ierr);
       ierr = nc_def_var(ncid[n],"Exy",NC_FLOAT,4,dimid,&varid_E[n*CONST_NDIM_2+5]); handle_nc_err(ierr);
    }
    // attribute: index in output snapshot, index w ghost in thread
    int g_start[] = { iosnap->i1_to_glob[n],
                      iosnap->j1_to_glob[n],
                      iosnap->k1_to_glob[n] };
    nc_put_att_int(ncid[n],NC_GLOBAL,"first_index_to_snapshot_output",
                   NC_INT,CONST_NDIM,g_start);

    int l_start[] = { snap_i1, snap_j1, snap_k1 };
    nc_put_att_int(ncid[n],NC_GLOBAL,"first_index_in_this_thread_with_ghosts",
                   NC_INT,CONST_NDIM,l_start);

    int l_count[] = { snap_di, snap_dj, snap_dk };
    nc_put_att_int(ncid[n],NC_GLOBAL,"index_stride_in_this_thread",
                   NC_INT,CONST_NDIM,l_count);
    nc_put_att_int(ncid[n],NC_GLOBAL,"coords_of_mpi_topo",
                   NC_INT,3,topoid);

    ierr = nc_enddef(ncid[n]); handle_nc_err(ierr);
  } // loop snap

  return ierr;
}




/*
 * 
 */

int
io_snap_nc_put(iosnap_t *iosnap,
               iosnap_nc_t *iosnap_nc,
               gd_t    *gd,
               md_t    *md,
               wav_t   *wav,
               float *w_pre_d,
               float *buff,
               int   nt_total,
               int   it,
               float time)
{
  int ierr = 0;

  int num_of_snap = iosnap->num_of_snap;
  size_t siz_iy = gd->siz_iy;
  size_t siz_iz = gd->siz_iz;
  size_t siz_icmp = gd->siz_icmp;

  for (int n=0; n<num_of_snap; n++)
  {
    int snap_i1  = iosnap->i1[n];
    int snap_j1  = iosnap->j1[n];
    int snap_k1  = iosnap->k1[n];
    int snap_ni  = iosnap->ni[n];
    int snap_nj  = iosnap->nj[n];
    int snap_nk  = iosnap->nk[n];
    int snap_di  = iosnap->di[n];
    int snap_dj  = iosnap->dj[n];
    int snap_dk  = iosnap->dk[n];

    int snap_it1 = iosnap->it1[n];
    int snap_dit = iosnap->dit[n];

    int snap_out_V = iosnap->out_vel[n];
    int snap_out_T = iosnap->out_stress[n];
    int snap_out_E = iosnap->out_strain[n];

    int snap_it_mod = (it - snap_it1) % snap_dit;
    int snap_it_num = (it - snap_it1) / snap_dit;
    int snap_nt_total = (nt_total - snap_it1) / snap_dit;

    int snap_max_num = snap_ni * snap_nj * snap_nk;
    float *buff_d = NULL;

    if (it>=snap_it1 && snap_it_num<=snap_nt_total && snap_it_mod==0)
    {
      size_t startp[] = { iosnap_nc->cur_it[n], 0, 0, 0 };
      size_t countp[] = { 1, snap_nk, snap_nj, snap_ni };
      size_t start_tdim = iosnap_nc->cur_it[n];

      // put time var
      nc_put_var1_float(iosnap_nc->ncid[n],iosnap_nc->timeid[n],&start_tdim,&time);
      int size = sizeof(float)*snap_max_num;
      buff_d = (float *) cuda_malloc(size);
      dim3 block(8,8,8);
      dim3 grid;
      grid.x = (snap_ni+block.x-1)/block.x;
      grid.y = (snap_nj+block.y-1)/block.y;
      grid.z = (snap_nk+block.z-1)/block.z;
      // vel
      if (snap_out_V==1)
      {

        io_snap_pack_buff<<<grid, block>>> (w_pre_d + wav->Vx_pos,
                 siz_iy,siz_iz,snap_i1,snap_ni,snap_di,snap_j1,snap_nj,
                 snap_dj,snap_k1,snap_nk,snap_dk,buff_d);
        CUDACHECK(cudaMemcpy(buff+0*siz_icmp,buff_d,size,cudaMemcpyDeviceToHost));
        nc_put_vara_float(iosnap_nc->ncid[n],iosnap_nc->varid_V[n*CONST_NDIM+0],
              startp,countp,buff+0*siz_icmp);

        io_snap_pack_buff<<<grid, block>>> (w_pre_d + wav->Vy_pos,
                 siz_iy,siz_iz,snap_i1,snap_ni,snap_di,snap_j1,snap_nj,
                 snap_dj,snap_k1,snap_nk,snap_dk,buff_d);
        CUDACHECK(cudaMemcpy(buff+1*siz_icmp,buff_d,size,cudaMemcpyDeviceToHost));
        nc_put_vara_float(iosnap_nc->ncid[n],iosnap_nc->varid_V[n*CONST_NDIM+1],
              startp,countp,buff+1*siz_icmp);

        io_snap_pack_buff<<<grid, block>>> (w_pre_d + wav->Vz_pos,
                 siz_iy,siz_iz,snap_i1,snap_ni,snap_di,snap_j1,snap_nj,
                 snap_dj,snap_k1,snap_nk,snap_dk,buff_d);
        CUDACHECK(cudaMemcpy(buff+2*siz_icmp,buff_d,size,cudaMemcpyDeviceToHost));
        nc_put_vara_float(iosnap_nc->ncid[n],iosnap_nc->varid_V[n*CONST_NDIM+2],
              startp,countp,buff+2*siz_icmp);
      }

      if (snap_out_T==1)
      {
        io_snap_pack_buff<<<grid, block>>> (w_pre_d + wav->Txx_pos,
                 siz_iy,siz_iz,snap_i1,snap_ni,snap_di,snap_j1,snap_nj,
                 snap_dj,snap_k1,snap_nk,snap_dk,buff_d);
        CUDACHECK(cudaMemcpy(buff+3*siz_icmp,buff_d,size,cudaMemcpyDeviceToHost));
        nc_put_vara_float(iosnap_nc->ncid[n],iosnap_nc->varid_T[n*CONST_NDIM_2+0],
              startp,countp,buff+3*siz_icmp);

        io_snap_pack_buff<<<grid, block>>> (w_pre_d + wav->Tyy_pos,
                 siz_iy,siz_iz,snap_i1,snap_ni,snap_di,snap_j1,snap_nj,
                 snap_dj,snap_k1,snap_nk,snap_dk,buff_d);
        CUDACHECK(cudaMemcpy(buff+4*siz_icmp,buff_d,size,cudaMemcpyDeviceToHost));
        nc_put_vara_float(iosnap_nc->ncid[n],iosnap_nc->varid_T[n*CONST_NDIM_2+1],
              startp,countp,buff+4*siz_icmp);
        
        io_snap_pack_buff<<<grid, block>>> (w_pre_d + wav->Tzz_pos,
                 siz_iy,siz_iz,snap_i1,snap_ni,snap_di,snap_j1,snap_nj,
                 snap_dj,snap_k1,snap_nk,snap_dk,buff_d);
        CUDACHECK(cudaMemcpy(buff+5*siz_icmp,buff_d,size,cudaMemcpyDeviceToHost));
        nc_put_vara_float(iosnap_nc->ncid[n],iosnap_nc->varid_T[n*CONST_NDIM_2+2],
              startp,countp,buff+5*siz_icmp);
        
        io_snap_pack_buff<<<grid, block>>> (w_pre_d + wav->Txz_pos,
                 siz_iy,siz_iz,snap_i1,snap_ni,snap_di,snap_j1,snap_nj,
                 snap_dj,snap_k1,snap_nk,snap_dk,buff_d);
        CUDACHECK(cudaMemcpy(buff+6*siz_icmp,buff_d,size,cudaMemcpyDeviceToHost));
        nc_put_vara_float(iosnap_nc->ncid[n],iosnap_nc->varid_T[n*CONST_NDIM_2+3],
              startp,countp,buff+6*siz_icmp);

        io_snap_pack_buff<<<grid, block>>> (w_pre_d + wav->Tyz_pos,
                 siz_iy,siz_iz,snap_i1,snap_ni,snap_di,snap_j1,snap_nj,
                 snap_dj,snap_k1,snap_nk,snap_dk,buff_d);
        CUDACHECK(cudaMemcpy(buff+7*siz_icmp,buff_d,size,cudaMemcpyDeviceToHost));
        nc_put_vara_float(iosnap_nc->ncid[n],iosnap_nc->varid_T[n*CONST_NDIM_2+4],
              startp,countp,buff+7*siz_icmp);

        io_snap_pack_buff<<<grid, block>>> (w_pre_d + wav->Txy_pos,
                 siz_iy,siz_iz,snap_i1,snap_ni,snap_di,snap_j1,snap_nj,
                 snap_dj,snap_k1,snap_nk,snap_dk,buff_d);
        CUDACHECK(cudaMemcpy(buff+8*siz_icmp,buff_d,size,cudaMemcpyDeviceToHost));
        nc_put_vara_float(iosnap_nc->ncid[n],iosnap_nc->varid_T[n*CONST_NDIM_2+5],
              startp,countp,buff+8*siz_icmp);
      }
      if (snap_out_E==1)
      {
        if (snap_out_T==0)
        {
          io_snap_pack_buff<<<grid, block>>> (w_pre_d + wav->Txx_pos,
                   siz_iy,siz_iz,snap_i1,snap_ni,snap_di,snap_j1,snap_nj,
                   snap_dj,snap_k1,snap_nk,snap_dk,buff_d);
          CUDACHECK(cudaMemcpy(buff+3*siz_icmp,buff_d,size,cudaMemcpyDeviceToHost));

          io_snap_pack_buff<<<grid, block>>> (w_pre_d + wav->Tyy_pos,
                   siz_iy,siz_iz,snap_i1,snap_ni,snap_di,snap_j1,snap_nj,
                   snap_dj,snap_k1,snap_nk,snap_dk,buff_d);
          CUDACHECK(cudaMemcpy(buff+4*siz_icmp,buff_d,size,cudaMemcpyDeviceToHost));
          
          io_snap_pack_buff<<<grid, block>>> (w_pre_d + wav->Tzz_pos,
                   siz_iy,siz_iz,snap_i1,snap_ni,snap_di,snap_j1,snap_nj,
                   snap_dj,snap_k1,snap_nk,snap_dk,buff_d);
          CUDACHECK(cudaMemcpy(buff+5*siz_icmp,buff_d,size,cudaMemcpyDeviceToHost));
          
          io_snap_pack_buff<<<grid, block>>> (w_pre_d + wav->Txz_pos,
                   siz_iy,siz_iz,snap_i1,snap_ni,snap_di,snap_j1,snap_nj,
                   snap_dj,snap_k1,snap_nk,snap_dk,buff_d);
          CUDACHECK(cudaMemcpy(buff+6*siz_icmp,buff_d,size,cudaMemcpyDeviceToHost));

          io_snap_pack_buff<<<grid, block>>> (w_pre_d + wav->Tyz_pos,
                   siz_iy,siz_iz,snap_i1,snap_ni,snap_di,snap_j1,snap_nj,
                   snap_dj,snap_k1,snap_nk,snap_dk,buff_d);
          CUDACHECK(cudaMemcpy(buff+7*siz_icmp,buff_d,size,cudaMemcpyDeviceToHost));

          io_snap_pack_buff<<<grid, block>>> (w_pre_d + wav->Txy_pos,
                   siz_iy,siz_iz,snap_i1,snap_ni,snap_di,snap_j1,snap_nj,
                   snap_dj,snap_k1,snap_nk,snap_dk,buff_d);
          CUDACHECK(cudaMemcpy(buff+8*siz_icmp,buff_d,size,cudaMemcpyDeviceToHost));
        }
        // convert to strain
        io_snap_stress_to_strain_eliso(md->lambda,md->mu,
                                       buff + 3*siz_icmp,   //Txx
                                       buff + 4*siz_icmp,   //Tyy
                                       buff + 5*siz_icmp,   //Tzz
                                       buff + 6*siz_icmp,   //Tyz
                                       buff + 7*siz_icmp,   //Txz
                                       buff + 8*siz_icmp,   //Txy
                                       buff + 9*siz_icmp,   //Exx
                                       buff + 10*siz_icmp,  //Eyy
                                       buff + 11*siz_icmp,  //Ezz
                                       buff + 12*siz_icmp,  //Eyz
                                       buff + 13*siz_icmp,  //Exz
                                       buff + 14*siz_icmp,  //Exy
                                       siz_iy,siz_iz,snap_i1,snap_ni,snap_di,snap_j1,snap_nj,
                                       snap_dj,snap_k1,snap_nk,snap_dk);
        // export
        nc_put_vara_float(iosnap_nc->ncid[n],iosnap_nc->varid_E[n*CONST_NDIM_2+0],
              startp,countp,buff + 9*siz_icmp);
        nc_put_vara_float(iosnap_nc->ncid[n],iosnap_nc->varid_E[n*CONST_NDIM_2+1],
              startp,countp,buff + 10*siz_icmp);
        nc_put_vara_float(iosnap_nc->ncid[n],iosnap_nc->varid_E[n*CONST_NDIM_2+2],
              startp,countp,buff + 11*siz_icmp);
        nc_put_vara_float(iosnap_nc->ncid[n],iosnap_nc->varid_E[n*CONST_NDIM_2+3],
              startp,countp,buff + 12*siz_icmp);
        nc_put_vara_float(iosnap_nc->ncid[n],iosnap_nc->varid_E[n*CONST_NDIM_2+4],
              startp,countp,buff + 13*siz_icmp);
        nc_put_vara_float(iosnap_nc->ncid[n],iosnap_nc->varid_E[n*CONST_NDIM_2+5],
              startp,countp,buff + 14*siz_icmp);

      }

      iosnap_nc->cur_it[n] += 1;

      CUDACHECK(cudaFree(buff_d));
    } // if it
  } // loop snap

  return ierr;
}

int
io_snap_stress_to_strain_eliso(float *lam3d,
                               float *mu3d,
                               float *Txx,
                               float *Tyy,
                               float *Tzz,
                               float *Tyz,
                               float *Txz,
                               float *Txy,
                               float *Exx,
                               float *Eyy,
                               float *Ezz,
                               float *Eyz,
                               float *Exz,
                               float *Exy,
                               size_t siz_iy,
                               size_t siz_iz,
                               int starti,
                               int counti,
                               int increi,
                               int startj,
                               int countj,
                               int increj,
                               int startk,
                               int countk,
                               int increk)
{
  size_t iptr_snap=0;
  size_t i,j,k,iptr,iptr_j,iptr_k;
  float lam,mu,E1,E2,E3,E0;

  for (int n3=0; n3<countk; n3++)
  {
    k = startk + n3 * increk;
    iptr_k = k * siz_iz;
    for (int n2=0; n2<countj; n2++)
    {
      j = startj + n2 * increj;
      iptr_j = j * siz_iy + iptr_k;

      for (int n1=0; n1<counti; n1++)
      {
        i = starti + n1 * increi;
        iptr = i + iptr_j;
        iptr_snap = n1 + n2 * counti + n3 * counti * countj;

        lam = lam3d[iptr];
        mu  =  mu3d[iptr];
        
        E1 = (lam + mu) / (mu * ( 3.0 * lam + 2.0 * mu));
        E2 = - lam / ( 2.0 * mu * (3.0 * lam + 2.0 * mu));
        E3 = 1.0 / mu;

        E0 = E2 * (Txx[iptr_snap] + Tyy[iptr_snap] + Tzz[iptr_snap]);

        Exx[iptr_snap] = E0 - (E2 - E1) * Txx[iptr_snap];
        Eyy[iptr_snap] = E0 - (E2 - E1) * Tyy[iptr_snap];
        Ezz[iptr_snap] = E0 - (E2 - E1) * Tzz[iptr_snap];
        Eyz[iptr_snap] = 0.5 * E3 * Tyz[iptr_snap];
        Exz[iptr_snap] = 0.5 * E3 * Txz[iptr_snap];
        Exy[iptr_snap] = 0.5 * E3 * Txy[iptr_snap];

      } // i
    } //j
  } //k

  return 0;
}
__global__ void
io_slice_pack_buff_x(int i, int nj, int nk, size_t siz_iy, size_t siz_iz, float *var, float* buff_d)
{
  size_t iy = blockIdx.x * blockDim.x + threadIdx.x;
  size_t iz = blockIdx.y * blockDim.y + threadIdx.y;
  if(iy < nj && iz < nk)
  {
    size_t iptr_slice = iy + iz*nj;
    size_t iptr = i + (iy+3) * siz_iy + (iz+3) * siz_iz; 
    buff_d[iptr_slice] = var[iptr];
  }
}

__global__ void
io_slice_pack_buff_y(int j, int ni, int nk, size_t siz_iy, size_t siz_iz, float *var, float *buff_d)
{
  size_t ix = blockIdx.x * blockDim.x + threadIdx.x;
  size_t iz = blockIdx.y * blockDim.y + threadIdx.y;
  if(ix < ni && iz < nk)
  {
    size_t iptr_slice = ix + iz*ni;
    size_t iptr = (ix+3) + j * siz_iy + (iz+3) * siz_iz; 
    buff_d[iptr_slice] = var[iptr];
  }
}

__global__ void
io_slice_pack_buff_z(int k, int ni, int nj, size_t siz_iy, size_t siz_iz, float *var, float *buff_d)
{
  size_t ix = blockIdx.x * blockDim.x + threadIdx.x;
  size_t iy = blockIdx.y * blockDim.y + threadIdx.y;
  if(ix < ni && iy < nj)
  {
    size_t iptr_slice = ix + iy*ni;
    size_t iptr = (ix+3) + (iy+3) * siz_iy + k * siz_iz; 
    buff_d[iptr_slice] = var[iptr];
  }
}

__global__ void
io_snap_pack_buff(float *var,
                  size_t siz_iy,
                  size_t siz_iz,
                  int starti,
                  int counti,
                  int increi,
                  int startj,
                  int countj,
                  int increj,
                  int startk,
                  int countk,
                  int increk,
                  float *buff_d)
{
  size_t ix = blockIdx.x * blockDim.x + threadIdx.x;
  size_t iy = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iz = blockIdx.z * blockDim.z + threadIdx.z;
  if(ix<counti && iy<countj && iz<countk)
  {
    size_t iptr_snap = ix + iy * counti + iz * counti *countj;
    size_t i = starti + ix * increi;
    size_t j = startj + iy * increj;
    size_t k = startk + iz * increk;
    size_t iptr = i + j * siz_iy + k * siz_iz;
    buff_d[iptr_snap] =  var[iptr];
  }
}

int
io_slice_nc_close(ioslice_nc_t *ioslice_nc)
{
  for (int n=0; n < ioslice_nc->num_of_slice_x; n++) {
    nc_close(ioslice_nc->ncid_slx[n]);
  }
  for (int n=0; n < ioslice_nc->num_of_slice_y; n++) {
    nc_close(ioslice_nc->ncid_sly[n]);
  }
  for (int n=0; n < ioslice_nc->num_of_slice_z; n++) {
    nc_close(ioslice_nc->ncid_slz[n]);
  }

  return 0;
}

int
io_snap_nc_close(iosnap_nc_t *iosnap_nc)
{
  for (int n=0; n < iosnap_nc->num_of_snap; n++)
  {
    nc_close(iosnap_nc->ncid[n]);
  }

  return 0;
}

int
ioslice_print(ioslice_t *ioslice)
{    
  fprintf(stdout, "-------------------------------------------------------\n");
  fprintf(stdout, "--> slice output information:\n");
  fprintf(stdout, "-------------------------------------------------------\n");

  fprintf(stdout, "--> num_of_slice_x = %d\n", ioslice->num_of_slice_x);
  for (int n=0; n<ioslice->num_of_slice_x; n++)
  {
    fprintf(stdout, "  #%d, i=%d, fname=%s\n", n, ioslice->slice_x_indx[n],ioslice->slice_x_fname[n]);
  }
  fprintf(stdout, "--> num_of_slice_y = %d\n", ioslice->num_of_slice_y);
  for (int n=0; n<ioslice->num_of_slice_y; n++)
  {
    fprintf(stdout, "  #%d, j=%d, fname=%s\n", n, ioslice->slice_y_indx[n],ioslice->slice_y_fname[n]);
  }
  fprintf(stdout, "--> num_of_slice_z = %d\n", ioslice->num_of_slice_z);
  for (int n=0; n<ioslice->num_of_slice_z; n++)
  {
    fprintf(stdout, "  #%d, k=%d, fname=%s\n", n, ioslice->slice_z_indx[n],ioslice->slice_z_fname[n]);
  }

  return 0;
}

int
iosnap_print(iosnap_t *iosnap)
{    
  fprintf(stdout, "--> num_of_snap = %d\n", iosnap->num_of_snap);
  fprintf(stdout, "#   i0 j0 k0 ni nj nk di dj dk it0 dit vel stress strain gi1 gj1 gk1\n");
  for (int n=0; n < iosnap->num_of_snap; n++)
  {
    fprintf(stdout, "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
              n,
              iosnap->i1[n], iosnap->j1[n], iosnap->k1[n],
              iosnap->ni[n], iosnap->nj[n], iosnap->nk[n],
              iosnap->di[n], iosnap->dj[n], iosnap->dk[n],
              iosnap->it1[n], iosnap->dit[n], 
              iosnap->out_vel[n],
              iosnap->out_stress[n],
              iosnap->out_strain[n],
              iosnap->i1_to_glob[n],
              iosnap->j1_to_glob[n],
              iosnap->k1_to_glob[n]);
  }

  return 0;
}

int
iorecv_print(iorecv_t *iorecv)
{    
  //fprintf(stdout, "\n");
  //fprintf(stdout, "--> station information.\n");
  //fprintf(stdout, " number_of_station  = %4d\n", blk->number_of_station);
  //fprintf(stdout, " seismo_format_sac  = %4d\n", blk->seismo_format_sac );
  //fprintf(stdout, " seismo_format_segy = %4d\n", blk->seismo_format_segy);
  //fprintf(stdout, " SeismoPrefix = %s\n", SeismoPrefix);
  //fprintf(stdout, "\n");

  //if(blk->number_of_station > 0)
  //{
  //    //fprintf(stdout, " station_indx:\n");
  //    fprintf(stdout, " stations             x           z           i           k:\n");
  //}

  //for(n=0; n<blk->number_of_station; n++)
  //{
  //    indx = 2*n;
  //    fprintf(stdout, "       %04d  %10.4e  %10.4e  %10d  %10d\n", n+1, 
  //            blk->station_coord[indx], blk->station_coord[indx+1],
  //            blk->station_indx [indx], blk->station_indx [indx+1]);
  //}
  //fprintf(stdout, "\n");

  return 0;
}

int
PG_slice_output(float *PG, gd_t *gd, char *output_dir, char *frame_coords, int *topoid)
{
  // output one time z slice
  // used for PGV PGA and PGD
  // cmp is PGV PGA PGD, component x, y, z
  int nx = gd->nx; 
  int ny = gd->ny;
  int ni = gd->ni; 
  int nj = gd->nj;
  int gni1 = gd->gni1; 
  int gnj1 = gd->gnj1; 
  char PG_cmp[CONST_NDIM_5][CONST_MAX_STRLEN] = {"PGV","PGVh","PGVx","PGVy","PGVz",
                                                 "PGA","PGAh","PGAx","PGAy","PGAz",
                                                 "PGD","PGDh","PGDx","PGDy","PGDz"}; 
  char out_file[CONST_MAX_STRLEN];
  sprintf(out_file,"%s/%s_%s.nc",output_dir,"PG_V_A_D",frame_coords);

  // create PGV output file
  int dimid[2];
  int varid[CONST_NDIM_5], ncid;
  int i,ierr;
  ierr = nc_create(out_file, NC_CLOBBER, &ncid); handle_nc_err(ierr);

  ierr = nc_def_dim(ncid, "j", ny, &dimid[0]); handle_nc_err(ierr);
  ierr = nc_def_dim(ncid, "i", nx, &dimid[1]); handle_nc_err(ierr);

  // define vars
  for(int i=0; i<CONST_NDIM_5; i++)
  {
    if(nc_def_var(ncid, PG_cmp[i], NC_FLOAT,2,dimid, &varid[i])) handle_nc_err(ierr);
  }
  int g_start[2] = {gni1,gnj1}; 
  int phy_size[2] = {ni,nj}; 
  nc_put_att_int(ncid,NC_GLOBAL,"global_index_of_first_physical_points",
                    NC_INT,2,g_start);
  nc_put_att_int(ncid,NC_GLOBAL,"count_index_of_physical_points",
                    NC_INT,2,phy_size);
  nc_put_att_int(ncid,NC_GLOBAL,"coords_of_mpi_topo",
                    NC_INT,3,topoid);

  ierr = nc_enddef(ncid); handle_nc_err(ierr);

  // add vars
  for(int i=0; i<CONST_NDIM_5; i++)
  {
  float *ptr = PG + i*nx*ny; 
  ierr = nc_put_var_float(ncid,varid[i],ptr);
  }
  // close file
  ierr = nc_close(ncid); handle_nc_err(ierr);

  return 0;
}

/*
 * get next non-comment line
*/

int
io_get_nextline(FILE *fp, char *str, int length)
{
  int ierr = 0;

  do
  {
    if (fgets(str, length, fp) == NULL)
    {
       ierr = 1;
       return ierr;
    }
  } while (str[0] == '#' || str[0] == '\n');

  // remove newline char
  int len = strlen(str);
  if (len > 0 && str[len-1] == '\n') {
    str[len-1] = '\0';
  }

  // for debug:
  //fprintf(stdout," --return: %s\n", str);

  return ierr;
}
int
io_fault_locate(gd_t *gd, 
                iofault_t *iofault,
                int number_fault,
                int *fault_x_index,
                char *output_fname_part,
                char *output_dir)
{
  int ierr = 0;
  iofault->siz_max_wrk = 0;

  iofault->fault_fname = (char **) fdlib_mem_malloc_2l_char(number_fault,
                                   CONST_MAX_STRLEN,"fault_fname");

  iofault->fault_local_index = (int *) malloc(number_fault * sizeof(int));

  iofault->number_fault = 0;

  for (int i=0; i<number_fault; i++)
  {
    int gi = fault_x_index[i];
    int gi_1 = gi+1;
    if(gd_info_gindx_is_inner_i(gi, gd)==1)
    {
      int islc = iofault->number_fault;

      iofault->fault_local_index[islc] =  gd_info_indx_glphy2lcext_i(gi, gd);
      sprintf(iofault->fault_fname[islc],"%s/fault_i%d_%s.nc",
                output_dir,gi_1,output_fname_part);

      iofault->number_fault += 1;

      size_t slice_siz = gd->nj * gd->nk;
      iofault->siz_max_wrk = slice_siz > iofault->siz_max_wrk ? 
                             slice_siz : iofault->siz_max_wrk;
    }
  }

  return ierr;
}

int
io_fault_nc_create(iofault_t *iofault, 
                   int ni, int nj, int nk,
                   int *topoid, iofault_nc_t *iofault_nc)
{
  int ierr = 0;
  int number_fault = iofault->number_fault;

  iofault_nc->number_fault = number_fault;
  int num_of_vars  = 20;  // not a fixed number, dependent on output
  iofault_nc->num_of_vars = num_of_vars;

  // malloc vars
  iofault_nc->ncid   = (int *)malloc(number_fault*sizeof(int));
  iofault_nc->varid  = (int *)malloc(num_of_vars*number_fault*sizeof(int));

  int dimid[3];
  for (int i=0; i<number_fault; i++)
  {
    // fault slice
    ierr = nc_create(iofault->fault_fname[i], NC_CLOBBER, &(iofault_nc->ncid[i])); handle_nc_err(ierr);
    ierr = nc_def_dim(iofault_nc->ncid[i], "time", NC_UNLIMITED, &dimid[0]);       handle_nc_err(ierr); 
    ierr = nc_def_dim(iofault_nc->ncid[i], "k"   , nk          , &dimid[1]);       handle_nc_err(ierr);   
    ierr = nc_def_dim(iofault_nc->ncid[i], "j"   , nj          , &dimid[2]);       handle_nc_err(ierr); 

    // define variables
    ierr = nc_def_var(iofault_nc->ncid[i], "time",      NC_FLOAT, 1, dimid+0, 
                    &(iofault_nc->varid[0+i*num_of_vars]));  
    handle_nc_err(ierr);
    ierr = nc_def_var(iofault_nc->ncid[i], "Tn" ,       NC_FLOAT, 3, dimid,   
                    &(iofault_nc->varid[1+i*num_of_vars]));
    handle_nc_err(ierr);
    ierr = nc_def_var(iofault_nc->ncid[i], "Ts1",       NC_FLOAT, 3, dimid,   
                    &(iofault_nc->varid[2+i*num_of_vars]));
    handle_nc_err(ierr);
    ierr = nc_def_var(iofault_nc->ncid[i], "Ts2",       NC_FLOAT, 3, dimid,   
                    &(iofault_nc->varid[3+i*num_of_vars]));
    handle_nc_err(ierr);
    ierr = nc_def_var(iofault_nc->ncid[i], "Vs",        NC_FLOAT, 3, dimid,   
                    &(iofault_nc->varid[4+i*num_of_vars]));
    handle_nc_err(ierr);
    ierr = nc_def_var(iofault_nc->ncid[i], "Vs1",       NC_FLOAT, 3, dimid,   
                    &(iofault_nc->varid[5+i*num_of_vars])); 
    handle_nc_err(ierr);
    ierr = nc_def_var(iofault_nc->ncid[i], "Vs2",       NC_FLOAT, 3, dimid,   
                    &(iofault_nc->varid[6+i*num_of_vars]));
    handle_nc_err(ierr);
    ierr = nc_def_var(iofault_nc->ncid[i], "Slip",      NC_FLOAT, 3, dimid,   
                    &(iofault_nc->varid[7+i*num_of_vars]));
    handle_nc_err(ierr);
    ierr = nc_def_var(iofault_nc->ncid[i], "Slip1",     NC_FLOAT, 3, dimid,   
                    &(iofault_nc->varid[8+i*num_of_vars]));
    handle_nc_err(ierr);   
    ierr = nc_def_var(iofault_nc->ncid[i], "Slip2",     NC_FLOAT, 3, dimid,   
                    &(iofault_nc->varid[9+i*num_of_vars]));
    handle_nc_err(ierr);   
    ierr = nc_def_var(iofault_nc->ncid[i], "Peak_vs",   NC_FLOAT, 2, dimid+1, 
                    &(iofault_nc->varid[10+i*num_of_vars]));
    handle_nc_err(ierr);   
    ierr = nc_def_var(iofault_nc->ncid[i], "Init_t0",   NC_FLOAT, 2, dimid+1, 
                    &(iofault_nc->varid[11+i*num_of_vars]));
    handle_nc_err(ierr);   

    // attribute: index info for plot
    nc_put_att_int(iofault_nc->ncid[i],NC_GLOBAL,"i_index_with_ghosts_in_this_thread",
                   NC_INT,1,iofault->fault_local_index+i);
    nc_put_att_int(iofault_nc->ncid[i],NC_GLOBAL,"coords_of_mpi_topo",
                   NC_INT,3,topoid);

    ierr = nc_enddef(iofault_nc->ncid[i]); handle_nc_err(ierr);
  }

  return ierr;
}

int
io_fault_nc_put(iofault_nc_t *iofault_nc,
                gd_t     *gd,
                fault_t  *F,
                fault_t  F_d,
                float *buff,
                int   it,
                float time)
{
  int ierr = 0;

  int   nj  = gd->nj;
  int   nk  = gd->nk;
  int   ny  = gd->ny;
  size_t size = sizeof(float) * nj * nk; 
  float *buff_d;
  buff_d = (float *) cuda_malloc(size);

  size_t startp[] = { it, 0, 0 };
  size_t countp[] = { 1, nk, nj};
  size_t start_tdim = it;
  int  num_of_vars = iofault_nc->num_of_vars;

  dim3 block(8,8);
  dim3 grid;
  grid.x = (nj+block.x-1)/block.x;
  grid.y = (nk+block.y-1)/block.y;
  for (int id=0; id<iofault_nc->number_fault; id++)
  {
    nc_put_var1_float(iofault_nc->ncid[id], iofault_nc->varid[0+id*num_of_vars],
                        &start_tdim, &time);

    // Tn
    io_fault_pack_buff<<<grid, block>>>(nj,nk,ny,id,F_d,F->cmp_pos[0],buff_d);
    CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));
    nc_put_vara_float(iofault_nc->ncid[id], iofault_nc->varid[1+id*num_of_vars], startp, countp, buff); 
    // Ts1  
    io_fault_pack_buff<<<grid, block>>>(nj,nk,ny,id,F_d,F->cmp_pos[1],buff_d);
    CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));
    nc_put_vara_float(iofault_nc->ncid[id], iofault_nc->varid[2+id*num_of_vars], startp, countp, buff); 
    // Ts2  
    io_fault_pack_buff<<<grid, block>>>(nj,nk,ny,id,F_d,F->cmp_pos[2],buff_d);
    CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));
    nc_put_vara_float(iofault_nc->ncid[id], iofault_nc->varid[3+id*num_of_vars], startp, countp, buff); 
    // Vs  
    io_fault_pack_buff<<<grid, block>>>(nj,nk,ny,id,F_d,F->cmp_pos[3],buff_d);
    CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));
    nc_put_vara_float(iofault_nc->ncid[id], iofault_nc->varid[4+id*num_of_vars], startp, countp, buff); 
    // Vs1  
    io_fault_pack_buff<<<grid, block>>>(nj,nk,ny,id,F_d,F->cmp_pos[4],buff_d);
    CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));
    nc_put_vara_float(iofault_nc->ncid[id], iofault_nc->varid[5+id*num_of_vars], startp, countp, buff); 
    // Vs2  
    io_fault_pack_buff<<<grid, block>>>(nj,nk,ny,id,F_d,F->cmp_pos[5],buff_d);
    CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));
    nc_put_vara_float(iofault_nc->ncid[id], iofault_nc->varid[6+id*num_of_vars], startp, countp, buff); 
    // Slip  
    io_fault_pack_buff<<<grid, block>>>(nj,nk,ny,id,F_d,F->cmp_pos[6],buff_d);
    CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));
    nc_put_vara_float(iofault_nc->ncid[id], iofault_nc->varid[7+id*num_of_vars], startp, countp, buff); 
    // Slip1  
    io_fault_pack_buff<<<grid, block>>>(nj,nk,ny,id,F_d,F->cmp_pos[7],buff_d);
    CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));
    nc_put_vara_float(iofault_nc->ncid[id], iofault_nc->varid[8+id*num_of_vars], startp, countp, buff); 
    // Slip2 
    io_fault_pack_buff<<<grid, block>>>(nj,nk,ny,id,F_d,F->cmp_pos[8],buff_d);
    CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));
    nc_put_vara_float(iofault_nc->ncid[id], iofault_nc->varid[9+id*num_of_vars], startp, countp, buff); 
  }

  CUDACHECK(cudaFree(buff_d));
  return ierr;
}

int
io_fault_end_t_nc_put(iofault_nc_t *iofault_nc,
                      gd_t     *gd,
                      fault_t  *F,
                      fault_t  F_d,
                      float *buff)
{
  int ierr = 0;

  int nj  = gd->nj;
  int nk  = gd->nk;
  int ny  = gd->ny;
  size_t size = sizeof(float) * nj * nk; 
  float *buff_d;
  buff_d = (float *) cuda_malloc(size);

  size_t startp[] = {  0, 0 };
  size_t countp[] = { nk, nj};
  int  num_of_vars = iofault_nc->num_of_vars;

  dim3 block(8,8);
  dim3 grid;
  grid.x = (nj+block.x-1)/block.x;
  grid.y = (nk+block.y-1)/block.y;

  for (int id=0; id<iofault_nc->number_fault; id++)
  {
    // peak_Vs
    io_fault_pack_buff<<<grid, block>>>(nj,nk,ny,id,F_d,F->cmp_pos[9],buff_d);
    CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));
    nc_put_vara_float(iofault_nc->ncid[id], iofault_nc->varid[10+id*num_of_vars], startp, countp, buff); 
    // init_t0
    io_fault_pack_buff<<<grid, block>>>(nj,nk,ny,id,F_d,F->cmp_pos[10],buff_d);
    CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));
    nc_put_vara_float(iofault_nc->ncid[id], iofault_nc->varid[11+id*num_of_vars], startp, countp, buff); 
  }
  CUDACHECK(cudaFree(buff_d));

  return ierr;
}

__global__ void
io_fault_pack_buff(int nj, int nk, int ny, int id, fault_t F, size_t cmp_pos, float* buff_d)
{
  size_t iy = blockIdx.x * blockDim.x + threadIdx.x;
  size_t iz = blockIdx.y * blockDim.y + threadIdx.y;
  fault_one_t *F_thisone = F.fault_one + id; 
  if(iy < nj && iz < nk)
  {
    size_t iptr_slice = iy + iz*nj;
    size_t iptr = (iy+3) + (iz+3) * ny; 
    buff_d[iptr_slice] = F_thisone->output[cmp_pos + iptr];
  }
}

int
io_fault_nc_close(iofault_nc_t *iofault_nc)
{
  for (int i=0; i<iofault_nc->number_fault; i++)
  {
    nc_close(iofault_nc->ncid[i]);
  }

  return 0;
}

/*
 * read in station list file and locate station
 */
int
io_fault_recv_read_locate(gd_t      *gd,
                          io_fault_recv_t  *io_fault_recv,
                          int       nt_total,
                          int       num_of_vars,
                          int       *fault_indx,
                          char      *in_filenm,
                          MPI_Comm  comm,
                          int       myid)
{
  FILE *fp;
  char line[500];

  io_fault_recv->total_number = 0;
  io_fault_recv->flag_swap = 0;
  if (!(fp = fopen (in_filenm, "rt")))
	{
    fprintf(stdout,"#########         ########\n");
    fprintf(stdout,"######### Warning ########\n");
    fprintf(stdout,"#########         ########\n");
    fprintf(stdout,"Cannot open input fault station file %s\n", in_filenm);
	  fflush (stdout);
	  return 0;
	}

  int total_point_y = gd->total_point_y;
  int total_point_z = gd->total_point_z;
  int gnj2 = gd->gnj2;
  int gnk2 = gd->gnk2;
  // number of station
  int num_recv;

  io_get_nextline(fp, line, 500);
  sscanf(line, "%d", &num_recv);

  io_fault_recv_one_t *fault_recvone = (io_fault_recv_one_t *)malloc(num_recv * sizeof(io_fault_recv_one_t));

  // read coord and locate

  int ir=0;
  int nr_this = 0; // in this thread

  int f_id;  //fault_id
  int ix, iy, iz; // global index
  float rx, ry, rz; //coords
  float rx_inc, ry_inc, rz_inc; //increment

  for (ir=0; ir<num_recv; ir++)
  {
    // read one line
    io_get_nextline(fp, line, 500);

    // get values
    sscanf(line, "%s %d %g %g", 
           fault_recvone[ir].name, &f_id, &ry, &rz);

    // need minus 1, due to C is start from 0
    f_id = f_id - 1;
    ry = ry-1;
    rz = rz-1;
    ix = fault_indx[f_id];
    rx_inc = 0;

    // do not take nearest value, but use smaller value
    iy = floor(ry);
    iz = floor(rz);
    ry_inc = ry - iy;
    rz_inc = rz - iz;
    // check recv in ghost region
    // if there is a point, perform fault variable exchange
    // exchange 1 point for interp
    if(iy == gnj2 && ry_inc >0)
    {
      io_fault_recv->flag_swap = 1;
    }
    if(iz == gnk2 && rz_inc >0)
    {
      io_fault_recv->flag_swap = 1;
    }

    if (gd_info_gindx_is_inner(ix,iy,iz,gd) == 1)
    {
      // convert to local index without ghost
      int i_local = gd_info_indx_glphy2lcext_j(ix,gd);
      int j_local = gd_info_indx_glphy2lcext_j(iy,gd);
      int k_local = gd_info_indx_glphy2lcext_k(iz,gd);

      rx = gd_coord_get_x(gd,i_local,j_local,k_local);
      ry = gd_coord_get_y(gd,i_local,j_local,k_local);
      rz = gd_coord_get_z(gd,i_local,j_local,k_local);

      io_fault_recv_one_t *this_recv = fault_recvone + nr_this;

      sprintf(this_recv->name, "%s", fault_recvone[ir].name);
      // get coord
      this_recv->x = rx;
      this_recv->y = ry;
      this_recv->z = rz;
      // set point
      this_recv->i=i_local;
      this_recv->j=j_local;
      this_recv->k=k_local;
      this_recv->di = rx_inc;
      this_recv->dj = ry_inc;
      this_recv->dk = rz_inc;
      this_recv->f_id = f_id;

      this_recv->indx1d[0] = j_local     + k_local * gd->ny;
      this_recv->indx1d[1] = (j_local+1) + k_local * gd->ny;
      this_recv->indx1d[2] = j_local     + (k_local+1) * gd->ny;
      this_recv->indx1d[3] = (j_local+1) + (k_local+1) * gd->ny;
      nr_this += 1;
    }
    if(myid==0)
    {
      if(iy<0 || iy>total_point_y-1 || iz<0 || iz>total_point_z-1 )
      {
        fprintf(stdout,"#########         ########\n");
        fprintf(stdout,"#########  Error  ########\n");
        fprintf(stdout,"#########         ########\n");
        fprintf(stdout,"fault_recv_number[%d] physical coordinates are outside calculation area !\n",ir+1);
        exit(1);
      }
    }
  }


  fclose(fp);
 
  io_fault_recv->total_number  = nr_this;
  io_fault_recv->fault_recvone = fault_recvone;
  io_fault_recv->max_nt        = nt_total;
  io_fault_recv->ncmp          = num_of_vars;

  // malloc seismo
  for (int ir=0; ir < io_fault_recv->total_number; ir++)
  {
    fault_recvone = io_fault_recv->fault_recvone + ir;
    fault_recvone->seismo = (float *) malloc(num_of_vars * nt_total * sizeof(float));
  }
  return 0;
}

int
io_fault_recv_keep(io_fault_recv_t *io_fault_recv, fault_t F_d, 
                   float *buff, int it, size_t siz_slice_yz)
{
  float Ly1, Ly2, Lz1, Lz2;
  int ncmp = F_d.ncmp-2; //0-8 variable 
  int size = sizeof(float)*4*ncmp;
  float *buff_d = (float *) cuda_malloc(size);
  size_t *indx1d_d = (size_t *) cuda_malloc(sizeof(size_t)*4);
  int iptr_sta;
  dim3 block(32);
  dim3 grid;
  grid.x = (ncmp+block.x-1)/block.x;

  for (int n=0; n < io_fault_recv->total_number; n++)
  {
    io_fault_recv_one_t *this_recv = io_fault_recv->fault_recvone + n;
    int id = this_recv->f_id;

    size_t *indx1d = this_recv->indx1d;
    CUDACHECK(cudaMemcpy(indx1d_d,indx1d,sizeof(size_t)*4,cudaMemcpyHostToDevice));

    // get coef of linear interp
    Ly2 = this_recv->dj; Ly1 = 1.0 - Ly2;
    Lz2 = this_recv->dk; Lz1 = 1.0 - Lz2;

    io_fault_recv_interp_pack_buff<<<grid, block>>> (id, F_d, buff_d, ncmp, siz_slice_yz, indx1d_d);
    CUDACHECK(cudaMemcpy(buff,buff_d,size,cudaMemcpyDeviceToHost));
    for (int icmp=0; icmp < ncmp; icmp++)
    {
      iptr_sta = icmp * io_fault_recv->max_nt + it;
      this_recv->seismo[iptr_sta] = buff[4*icmp+0] * Ly1 * Lz1
                                  + buff[4*icmp+1] * Ly2 * Lz1
                                  + buff[4*icmp+2] * Ly1 * Lz2
                                  + buff[4*icmp+3] * Ly2 * Lz2;
    }
  }

  return 0;
}

__global__ void
io_fault_recv_interp_pack_buff(int id, fault_t  F_d, float *buff_d, int ncmp, size_t siz_slice_yz, size_t *indx1d_d)
{
  size_t ix = blockIdx.x * blockDim.x + threadIdx.x;
  fault_one_t *F_thisone = F_d.fault_one + id; 
  if(ix < ncmp)
  {
    buff_d[4*ix+0] = F_thisone->output[ix*siz_slice_yz+indx1d_d[0]];
    buff_d[4*ix+1] = F_thisone->output[ix*siz_slice_yz+indx1d_d[1]];
    buff_d[4*ix+2] = F_thisone->output[ix*siz_slice_yz+indx1d_d[2]];
    buff_d[4*ix+3] = F_thisone->output[ix*siz_slice_yz+indx1d_d[3]];
  }
}


int
io_fault_recv_output_sac(io_fault_recv_t *io_fault_recv,
                         float dt,
                         int num_of_vars,
                         char *output_dir,
                         char *err_message)
{
  // use fake evt_x etc. since did not implement gather evt_x by mpi
  float evt_x = 0.0;
  float evt_y = 0.0;
  float evt_z = 0.0;
  float evt_d = 0.0;
  char ou_file[CONST_MAX_STRLEN];
  char cmp_name[num_of_vars][CONST_MAX_STRLEN] = {"Tn","Ts1","Ts2",
                                                  "Vs", "Vs1","Vs2",
                                                  "Slip", "Slip1", "Slip2"};

  for (int ir=0; ir < io_fault_recv->total_number; ir++)
  {
    io_fault_recv_one_t *this_recv = io_fault_recv->fault_recvone + ir;

    //fprintf(stdout,"=== Debug: num_of_vars=%d\n",num_of_vars);fflush(stdout);
    for (int icmp=0; icmp < num_of_vars; icmp++)
    {
      //fprintf(stdout,"=== Debug: icmp=%d\n",icmp);fflush(stdout);

      float *this_trace = this_recv->seismo + icmp * io_fault_recv->max_nt;

      sprintf(ou_file,"%s/fault_%s.%s.sac", output_dir, 
                      this_recv->name, cmp_name[icmp]);

      //fprintf(stdout,"=== Debug: icmp=%d,ou_file=%s\n",icmp,ou_file);fflush(stdout);

      sacExport1C1R(ou_file,
            this_trace,
            evt_x, evt_y, evt_z, evt_d,
            this_recv->x, this_recv->y, this_recv->z,
            dt, dt, io_fault_recv->max_nt, err_message);
    }
  }

  return 0;
}

