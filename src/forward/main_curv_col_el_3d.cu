/*******************************************************************************
 * Curvilinear Grid Finite Difference For Fault Dynamic Simulation 
 ******************************************************************************/

// NOTE: fault info
//  n -> normal Tn 
//  1 -> strike Ts1
//  2 -> dip    Ts2

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stddef.h>
#include <time.h>
#include <mpi.h>

#include "constants.h"
#include "par_t.h"
#include "blk_t.h"

#include "media_discrete_model.h"
#include "drv_rk_curv_col.h"
#include "cuda_common.h"

int main(int argc, char** argv)
{
  int gpu_id_start;
  char *par_fname;
  char err_message[CONST_MAX_STRLEN];

  //-------------------------------------------------------------------------------
  // start MPI and read par
  //-------------------------------------------------------------------------------

  // init MPI

  int myid, mpi_size;
  MPI_Init(&argc, &argv);
  MPI_Comm comm = MPI_COMM_WORLD;
  MPI_Comm_rank(comm, &myid);
  MPI_Comm_size(comm, &mpi_size);

  // get commond-line argument
  if (myid==0) 
  {
    // argc checking
    if (argc < 3) {
      fprintf(stdout,"usage: cgfdm3d_elastic <par_file> \n");
      MPI_Finalize();
      exit(1);
    }

    par_fname = argv[1];

    if (argc >= 3) {
      gpu_id_start = atoi(argv[2]); // gpu_id_start number
      fprintf(stdout,"gpu_id_start=%d\n",gpu_id_start ); fflush(stdout);
    }
    MPI_Bcast(&gpu_id_start, 1, MPI_INT, 0, comm);
  }
  else
  {
    MPI_Bcast(&gpu_id_start, 1, MPI_INT, 0, comm);
  }

  //-------------------------------------------------------------------------------
  // initial gpu device after start MPI
  //-------------------------------------------------------------------------------
  setDeviceBeforeInit(gpu_id_start);

  if (myid==0) fprintf(stdout,"comm=%d, size=%d\n", comm, mpi_size); 
  if (myid==0) fprintf(stdout,"par file =  %s\n", par_fname); 

  // read par
  par_t *par = (par_t *) malloc(sizeof(par_t));
  par_mpi_get(par_fname, myid, comm, par);
  if (myid==0) par_print(par);

  //-------------------------------------------------------------------------------
  // init blk_t
  //-------------------------------------------------------------------------------

  if (myid==0) fprintf(stdout,"create blk ...\n"); 

  // malloc blk
  blk_t *blk = (blk_t *) malloc(sizeof(blk_t));

  // malloc inner vars
  blk_init(blk, myid);

  fd_t            *fd            = blk->fd    ;
  mympi_t         *mympi         = blk->mympi ;
  gd_t            *gd            = blk->gd;
  gd_metric_t     *gd_metric     = blk->gd_metric;
  md_t            *md            = blk->md;
  wav_t           *wav           = blk->wav;
  bdryfree_t      *bdryfree      = blk->bdryfree;
  bdrypml_t       *bdrypml       = blk->bdrypml;
  bdryexp_t       *bdryexp       = blk->bdryexp;
  iorecv_t        *iorecv        = blk->iorecv;
  io_fault_recv_t *io_fault_recv = blk->io_fault_recv;
  ioline_t        *ioline        = blk->ioline;
  iofault_t       *iofault       = blk->iofault;
  ioslice_t       *ioslice       = blk->ioslice;
  iosnap_t        *iosnap        = blk->iosnap;
  fault_t         *fault         = blk->fault;
  fault_coef_t    *fault_coef    = blk->fault_coef;
  fault_wav_t     *fault_wav     = blk->fault_wav;

  // set up fd_t
  if (myid==0) fprintf(stdout,"set scheme ...\n"); 
  fd_set_macdrp(fd);

  // set mpi
  if (myid==0) fprintf(stdout,"set mpi topo ...\n"); 
  mympi_set(mympi,
            par->number_of_mpiprocs_x,
            par->number_of_mpiprocs_y,
            par->number_of_mpiprocs_z,
            comm,
            myid);

  // set gdinfo
  gd_info_set(gd, mympi,
              par->number_of_total_grid_points_x,
              par->number_of_total_grid_points_y,
              par->number_of_total_grid_points_z,
              par->bdry_has_cfspml,
              par->abs_num_of_layers,
              fd->fdx_nghosts,
              fd->fdy_nghosts,
              fd->fdz_nghosts);
              

  // set str in blk
  blk_set_output(blk, mympi,
                 par->output_dir,
                 par->grid_export_dir,
                 par->media_export_dir);

  //-------------------------------------------------------------------------------
  //-- grid generation or import
  //-------------------------------------------------------------------------------

  if (myid==0) fprintf(stdout,"allocate grid vars ...\n"); 

  // malloc var in gd
  gd_curv_init(gd);

  // malloc var in gd_metric
  gd_curv_metric_init(gd, gd_metric);

  // generate grid coord
  switch (par->grid_generation_itype)
  {
    case FAULT_PLANE : {

      if (myid==0) fprintf(stdout,"gerate grid using fault plane...\n"); 
      gd_curv_gen_fault(gd, par->number_fault, par->fault_x_index, par->dh, par->fault_coord_dir);
      if (myid==0) fprintf(stdout,"exchange coords ...\n"); 
      gd_exchange(gd,gd->v4d,gd->ncmp,mympi->neighid,mympi->topocomm);

      break;
    }

    case GRID_IMPORT : {

      if (myid==0) fprintf(stdout,"import grid ...\n"); 
      gd_curv_coord_import(gd, blk->output_fname_part, par->grid_import_dir);
      if (myid==0) fprintf(stdout,"exchange coords ...\n"); 
      gd_exchange(gd,gd->v4d,gd->ncmp,mympi->neighid,mympi->topocomm);

      break;
    }
  }

  // cal min/max of this thread
  gd_curv_set_minmax(gd);
  if (myid==0) {
    fprintf(stdout,"calculated min/max of grid/tile/cell\n"); 
    fflush(stdout);
  }

  // output
  if (par->is_export_grid==1)
  {
    if (myid==0) fprintf(stdout,"export coord to file ...\n"); 
    gd_curv_coord_export(gd,
                         blk->output_fname_part,
                         blk->grid_export_dir);
  } else {
    if (myid==0) fprintf(stdout,"do not export coord\n"); 
  }
  fprintf(stdout, " --> done\n"); fflush(stdout);

  // cal metrics and output for QC
  switch (par->metric_method_itype)
  {
    case PAR_METRIC_CALCULATE : {

      if (myid==0) fprintf(stdout,"calculate metrics ...\n"); 
      gd_curv_metric_cal(gd, gd_metric);

      break;
    }
    case PAR_METRIC_IMPORT : {

      if (myid==0) fprintf(stdout,"import metric file ...\n"); 
      gd_curv_metric_import(gd, gd_metric, blk->output_fname_part, par->metric_import_dir);

      break;
    }
  }
  if (myid==0) { fprintf(stdout, " --> done\n"); fflush(stdout); }

  // export metric
  if (par->is_export_metric==1)
  {
    if (myid==0) fprintf(stdout,"export metric to file ...\n"); 
    gd_curv_metric_export(gd,gd_metric,
                          blk->output_fname_part,
                          blk->grid_export_dir);
  } else {
    if (myid==0) fprintf(stdout,"do not export metric\n"); 
  }
  if (myid==0) { fprintf(stdout, " --> done\n"); fflush(stdout); }

  //-------------------------------------------------------------------------------
  //-- media generation or import
  //-------------------------------------------------------------------------------

  // allocate media vars
  if (myid==0) {fprintf(stdout,"allocate media vars ...\n"); fflush(stdout);}
  md_init(gd, md, par->media_itype, par->visco_itype);

  time_t t_start_md = time(NULL);
  // read or discrete velocity model
  switch (par->media_input_itype)
  {
    case PAR_MEDIA_CODE : {

      if (myid==0) fprintf(stdout,"generate simple medium in code ...\n"); 

      if (md->medium_type == CONST_MEDIUM_ELASTIC_ISO) {
        md_gen_uniform_el_iso(md);
      }

      if (md->medium_type == CONST_MEDIUM_ELASTIC_VTI) {
        md_gen_uniform_el_vti(md);
      }

      if (md->medium_type == CONST_MEDIUM_ELASTIC_ANISO) {
        md_gen_uniform_el_aniso(md);
      }

      if (md->visco_type == CONST_VISCO_GRAVES_QS) {
        md_gen_uniform_Qs(md, par->visco_Qs_freq);
      }

      break;
    }

    case PAR_MEDIA_IMPORT : {

      if (myid==0) fprintf(stdout,"import discrete medium file ...\n"); 
      md_import(gd, md, blk->output_fname_part, par->media_import_dir);

      break;
    }

    case PAR_MEDIA_3LAY : {

      if (myid==0) fprintf(stdout,"read and discretize 3D layer medium file ...\n"); 

      if (md->medium_type == CONST_MEDIUM_ELASTIC_ISO)
      {
          media_layer2model_el_iso(md->lambda, md->mu, md->rho,
                                   gd->x3d, gd->y3d, gd->z3d,
                                   gd->nx, gd->ny, gd->nz,
                                   MEDIA_USE_CURV,
                                   par->media_input_file,
                                   par->equivalent_medium_method);
      }
      else if (md->medium_type == CONST_MEDIUM_ELASTIC_VTI)
      {
          media_layer2model_el_vti(md->rho, md->c11, md->c33,
                                   md->c55,md->c66,md->c13,
                                   gd->x3d, gd->y3d, gd->z3d,
                                   gd->nx, gd->ny, gd->nz,
                                   MEDIA_USE_CURV,
                                   par->media_input_file,
                                   par->equivalent_medium_method);
      } else if (md->medium_type == CONST_MEDIUM_ELASTIC_ANISO)
      {
          media_layer2model_el_aniso(md->rho,
                                   md->c11,md->c12,md->c13,md->c14,md->c15,md->c16,
                                           md->c22,md->c23,md->c24,md->c25,md->c26,
                                                   md->c33,md->c34,md->c35,md->c36,
                                                           md->c44,md->c45,md->c46,
                                                                   md->c55,md->c56,
                                                                           md->c66,
                                   gd->x3d, gd->y3d, gd->z3d,
                                   gd->nx, gd->ny, gd->nz,
                                   MEDIA_USE_CURV,
                                   par->media_input_file,
                                   par->equivalent_medium_method);
      }

      break;
    }

    case PAR_MEDIA_3GRD : {

      if (myid==0) fprintf(stdout,"read and descretize 3D grid medium file ...\n");

      if (md->medium_type == CONST_MEDIUM_ELASTIC_ISO)
      {
          media_grid2model_el_iso(md->rho,md->lambda, md->mu,
                                   gd->x3d, gd->y3d, gd->z3d,
                                   gd->nx, gd->ny, gd->nz,
                                   gd->xmin,gd->xmax,
                                   gd->ymin,gd->ymax,
                                   MEDIA_USE_CURV,
                                   par->media_input_file,
                                   par->equivalent_medium_method);
      }
      else if (md->medium_type == CONST_MEDIUM_ELASTIC_VTI)
      {
          media_grid2model_el_vti(md->rho, md->c11, md->c33,
                                   md->c55,md->c66,md->c13,
                                   gd->x3d, gd->y3d, gd->z3d,
                                   gd->nx, gd->ny, gd->nz,
                                   gd->xmin,gd->xmax,
                                   gd->ymin,gd->ymax,
                                   MEDIA_USE_CURV,
                                   par->media_input_file,
                                   par->equivalent_medium_method);
      } else if (md->medium_type == CONST_MEDIUM_ELASTIC_ANISO)
      {
          media_grid2model_el_aniso(md->rho,
                                   md->c11,md->c12,md->c13,md->c14,md->c15,md->c16,
                                           md->c22,md->c23,md->c24,md->c25,md->c26,
                                                   md->c33,md->c34,md->c35,md->c36,
                                                           md->c44,md->c45,md->c46,
                                                                   md->c55,md->c56,
                                                                           md->c66,
                                   gd->x3d, gd->y3d, gd->z3d,
                                   gd->nx, gd->ny, gd->nz,
                                   gd->xmin,gd->xmax,
                                   gd->ymin,gd->ymax,
                                   MEDIA_USE_CURV,
                                   par->media_input_file,
                                   par->equivalent_medium_method);
      }

      break;
    }

    case PAR_MEDIA_3BIN : {

      if (myid==0) fprintf(stdout,"read and descretize 3D bin medium file ...\n"); 

      if (md->medium_type == CONST_MEDIUM_ELASTIC_ISO)
      {
          media_bin2model_el_iso(md->rho,md->lambda, md->mu, 
                                 gd->x3d, gd->y3d, gd->z3d,
                                 gd->nx, gd->ny, gd->nz,
                                 gd->xmin,gd->xmax,
                                 gd->ymin,gd->ymax,
                                 MEDIA_USE_CURV,
                                 par->bin_order,
                                 par->bin_size,
                                 par->bin_spacing,
                                 par->bin_origin,
                                 par->bin_file_rho,
                                 par->bin_file_vp,
                                 par->bin_file_vs);
      }
      else if (md->medium_type == CONST_MEDIUM_ELASTIC_VTI)
      {
        fprintf(stdout,"error: not implement reading bin file for MEDIUM_ELASTIC_VTI\n");
        fflush(stdout);
        exit(1);
          /*
          media_bin2model_el_vti_thomsen(md->rho, md->c11, md->c33,
                                   md->c55,md->c66,md->c13,
                                   gd->x3d, gd->y3d, gd->z3d,
                                   gd->nx, gd->ny, gd->nz,
                                   gd->xmin,gd->xmax,
                                   gd->ymin,gd->ymax,
                                   MEDIA_USE_CURV,
                                   par->bin_order,
                                   par->bin_size,
                                   par->bin_spacing,
                                   par->bin_origin,
                                   par->bin_file_rho,
                                   par->bin_file_vp,
                                   par->bin_file_epsilon,
                                   par->bin_file_delta,
                                   par->bin_file_gamma);
        */
      }
      else if (md->medium_type == CONST_MEDIUM_ELASTIC_ANISO)
      {
        fprintf(stdout,"error: not implement reading bin file for MEDIUM_ELASTIC_ANISO\n");
        fflush(stdout);
        exit(1);
          /*
          media_bin2model_el_aniso(md->rho,
                                   md->c11,md->c12,md->c13,md->c14,md->c15,md->c16,
                                           md->c22,md->c23,md->c24,md->c25,md->c26,
                                                   md->c33,md->c34,md->c35,md->c36,
                                                           md->c44,md->c45,md->c46,
                                                                   md->c55,md->c56,
                                                                           md->c66,
                                   gd->x3d, gd->y3d, gd->z3d,
                                   gd->nx, gd->ny, gd->nz,
                                   gd->xmin,gd->xmax,
                                   gd->ymin,gd->ymax,
                                   MEDIA_USE_CURV,
                                   par->bin_order,
                                   par->bin_size,
                                   par->bin_spacing,
                                   par->bin_origin,
                                   par->bin_file_rho,
                                   par->bin_file_c11,
                                   par->bin_file_c12,
                                   par->bin_file_c13,
                                   par->bin_file_c14,
                                   par->bin_file_c15,
                                   par->bin_file_c16,
                                   par->bin_file_c22,
                                   par->bin_file_c23,
                                   par->bin_file_c24,
                                   par->bin_file_c25,
                                   par->bin_file_c26,
                                   par->bin_file_c33,
                                   par->bin_file_c34,
                                   par->bin_file_c35,
                                   par->bin_file_c36,
                                   par->bin_file_c44,
                                   par->bin_file_c45,
                                   par->bin_file_c46,
                                   par->bin_file_c55,
                                   par->bin_file_c56,
                                   par->bin_file_c66);
        */
      }

      break;
    } 
  }

  MPI_Barrier(comm);
  time_t t_end_md = time(NULL);
  
  if (myid==0) {
    fprintf(stdout,"media Time of time :%f s \n", difftime(t_end_md,t_start_md));
  }
  // export grid media
  if (par->is_export_media==1)
  {
    if (myid==0) fprintf(stdout,"export discrete medium to file ...\n"); 

    md_export(gd, md,
              blk->output_fname_part,
              blk->media_export_dir);
  } else {
    if (myid==0) fprintf(stdout,"do not export medium\n"); 
  }

  //-------------------------------------------------------------------------------
  //-- estimate/check/set time step
  //-------------------------------------------------------------------------------

  float   t0 = par->time_start;
  float   dt = par->size_of_time_step;
  int     nt_total = par->number_of_time_steps+1;

  if (par->time_check_stability==1)
  {
    float dt_est[mpi_size];
    float dtmax, dtmaxVp, dtmaxL;
    int   dtmaxi, dtmaxj, dtmaxk;

    //-- estimate time step
    if (myid==0) fprintf(stdout,"   estimate time step ...\n"); 
    blk_dt_esti_curv(gd,md,fd->CFL,
            &dtmax, &dtmaxVp, &dtmaxL, &dtmaxi, &dtmaxj, &dtmaxk);
    
    //-- print for QC
    fprintf(stdout, "-> topoid=[%d,%d,%d], dtmax=%f, Vp=%f, L=%f, i=%d, j=%d, k=%d\n",
            mympi->topoid[0],mympi->topoid[1], mympi->topoid[2], dtmax, dtmaxVp, dtmaxL, dtmaxi, dtmaxj, dtmaxk);
    
    // receive dtmax from each proc
    MPI_Allgather(&dtmax,1,MPI_REAL,dt_est,1,MPI_REAL,MPI_COMM_WORLD);
  
    if (myid==0)
    {
       int dtmax_mpi_id = 0;
       dtmax = 1e19;
       for (int n=0; n < mpi_size; n++)
       {
        fprintf(stdout,"max allowed dt at each proc: id=%d, dtmax=%g\n", n, dt_est[n]);
        if (dtmax > dt_est[n]) {
          dtmax = dt_est[n];
          dtmax_mpi_id = n;
        }
       }
       fprintf(stdout,"Global maximum allowed time step is %g at thread %d\n", dtmax, dtmax_mpi_id);

       // check valid
       if (dtmax <= 0.0) {
          fprintf(stderr,"ERROR: maximum dt <= 0, stop running\n");
          MPI_Abort(MPI_COMM_WORLD,-1);
       }

       //-- auto set stept
       if (dt < 0.0) {
          dt       = blk_keep_three_digi(dtmax);
          nt_total = (int) (par->time_window_length / dt + 0.5);

          fprintf(stdout, "-> Set dt       = %g according to maximum allowed value\n", dt);
          fprintf(stdout, "-> Set nt_total = %d\n", nt_total);
       }

       //-- if input dt, check value
       if (dtmax < dt) {
          fprintf(stdout, "Serious Error: dt=%f > dtmax=%f, stop!\n", dt, dtmax);
          MPI_Abort(MPI_COMM_WORLD, -1);
       }
    }
    
    //-- from root to all threads
    MPI_Bcast(&dt      , 1, MPI_REAL, 0, MPI_COMM_WORLD);
    MPI_Bcast(&nt_total, 1, MPI_INT , 0, MPI_COMM_WORLD);
  }

  //-------------------------------------------------------------------------------
  //-- fault init
  //-------------------------------------------------------------------------------

  fault_coef_init(fault_coef, gd, par->number_fault, par->fault_x_index); 
  fault_coef_cal(gd, gd_metric, md, fault_coef);
  fault_init(fault, gd, par->number_fault, par->fault_x_index);
  fault_set(fault, fault_coef, gd, par->bdry_has_free, par->fault_grid, par->init_stress_dir);
  fault_wav_init(gd, fault_wav, par->number_fault, par->fault_x_index, fd->num_rk_stages);

  //-------------------------------------------------------------------------------
  //-- allocate main var
  //-------------------------------------------------------------------------------

  if (myid==0) fprintf(stdout,"allocate solver vars ...\n"); 
  wav_init(gd, wav, fd->num_rk_stages);

  //-------------------------------------------------------------------------------
  //-- setup output, may require coord info
  //-------------------------------------------------------------------------------

  if (myid==0) fprintf(stdout,"setup output info ...\n"); 

  // receiver: need to do
  io_recv_read_locate(gd, iorecv,
                      nt_total, wav->ncmp, 
                      par->number_of_mpiprocs_z,
                      par->in_station_file,
                      comm, myid);

  // Tn Ts1 Ts2 Vs Vs1 Vs2 Slip Slip1 Slip2
  int fault_ncmp = fault->ncmp - 2;  //=9
  io_fault_recv_read_locate(gd, io_fault_recv,
                            nt_total, fault_ncmp, 
                            par->fault_x_index,
                            par->fault_station_file,
                            comm, myid);
  // receive flag_exchange_var from each proc
  int sendbuf = io_fault_recv->flag_swap;
  MPI_Allreduce(&sendbuf,&io_fault_recv->flag_swap,1,MPI_INT,MPI_MAX,comm);
  if(myid == 0 && io_fault_recv->flag_swap == 1)
  {
    fprintf(stdout,"########################################################\n");
    fprintf(stdout,"have fault recv in ghost region, need exchange fault var\n");
    fprintf(stdout,"########################################################\n");
    fflush(stdout);
  }

  // line
  io_line_locate(gd, ioline,
                 wav->ncmp,
                 nt_total,
                 par->number_of_receiver_line,
                 par->receiver_line_index_start,
                 par->receiver_line_index_incre,
                 par->receiver_line_count,
                 par->receiver_line_name);
  
  // fault slice
  io_fault_locate(gd,iofault,
                  par->number_fault, 
                  par->fault_x_index, 
                  blk->output_fname_part,
                  blk->output_dir);
                  
  // slice
  io_slice_locate(gd, ioslice,
                  par->number_of_slice_x,
                  par->number_of_slice_y,
                  par->number_of_slice_z,
                  par->slice_x_index,
                  par->slice_y_index,
                  par->slice_z_index,
                  blk->output_fname_part,
                  blk->output_dir);
  
  // snapshot
  io_snapshot_locate(gd, iosnap,
                     par->number_of_snapshot,
                     par->snapshot_name,
                     par->snapshot_index_start,
                     par->snapshot_index_count,
                     par->snapshot_index_incre,
                     par->snapshot_time_start,
                     par->snapshot_time_incre,
                     par->snapshot_save_velocity,
                     par->snapshot_save_stress,
                     par->snapshot_save_strain,
                     blk->output_fname_part,
                     blk->output_dir);

  //-------------------------------------------------------------------------------
  //-- absorbing boundary etc auxiliary variables
  //-------------------------------------------------------------------------------

  if (par->bdry_has_cfspml == 1)
  {
    if (myid==0) fprintf(stdout,"setup absorbingg pml boundary ...\n"); 
  
    bdry_pml_set(gd, wav, bdrypml,
                 mympi->neighid,
                 par->cfspml_is_sides,
                 par->abs_num_of_layers,
                 par->cfspml_alpha_max,
                 par->cfspml_beta_max,
                 par->cfspml_velocity);
  }

  if (par->bdry_has_ablexp == 1)
  {
    if (myid==0) fprintf(stdout,"setup sponge layer ...\n"); 

    bdry_ablexp_set(gd, wav, bdryexp,
                    mympi->neighid,
                    par->ablexp_is_sides,
                    par->abs_num_of_layers,
                    par->ablexp_velocity,
                    dt,
                    mympi->topoid);
  }
  //-------------------------------------------------------------------------------
  //-- free surface preproc
  //-------------------------------------------------------------------------------

  if (myid==0) fprintf(stdout,"cal free surface matrix ...\n"); 

  if (par->bdry_has_free == 1)
  {
    bdry_free_set(gd, bdryfree, mympi->neighid, par->free_is_sides);
  }

  //-------------------------------------------------------------------------------
  //-- setup mesg
  //-------------------------------------------------------------------------------

  if (myid==0) fprintf(stdout,"init mesg ...\n"); 
  macdrp_mesg_init(mympi, fd, gd->ni, gd->nj, gd->nk,
                  wav->ncmp);
  macdrp_fault_mesg_init(mympi, fd, gd->nj, gd->nk,
                  fault_wav->ncmp, par->number_fault); 
  // output 9 varialbe, need -2
  if(io_fault_recv->flag_swap == 1)
  {
    int ncmp_out = fault->ncmp-2;
    macdrp_fault_output_mesg_init(mympi, fd, gd->nj, gd->nk,
                    ncmp_out, par->number_fault);
  }

  //-------------------------------------------------------------------------------
  //-- qc
  //-------------------------------------------------------------------------------

  mympi_print(mympi);

  gd_info_print(gd);

  ioslice_print(ioslice);

  iosnap_print(iosnap);

  //-------------------------------------------------------------------------------
  //-- slover
  //-------------------------------------------------------------------------------
  
  // convert rho to 1 / rho to reduce number of arithmetic cal
  md_rho_to_slow(md->rho, md->siz_icmp);

  if (myid==0) fprintf(stdout,"start solver ...\n"); 
  
  time_t t_start = time(NULL);

  drv_rk_curv_col_allstep(fd,gd,gd_metric,md,par,
                          bdryfree,bdrypml,bdryexp,wav,mympi,
                          fault_coef,fault,fault_wav,
                          iorecv,ioline,iofault,ioslice,iosnap,
                          io_fault_recv,
                          dt,nt_total,t0,
                          blk->output_fname_part,
                          blk->output_dir);

  time_t t_end = time(NULL);
  
  if (myid==0) {
    fprintf(stdout,"\n\nRuning Time of time :%f s \n", difftime(t_end,t_start));
  }

  //-------------------------------------------------------------------------------
  //-- save station and line seismo to sac
  //-------------------------------------------------------------------------------
  io_recv_output_sac(iorecv,dt,wav->ncmp,wav->cmp_name,
                      blk->output_dir,err_message);

  io_fault_recv_output_sac(io_fault_recv,dt,fault_ncmp,
                           blk->output_dir,err_message);

  if(md->medium_type == CONST_MEDIUM_ELASTIC_ISO) {
    io_recv_output_sac_el_iso_strain(iorecv,md->lambda,md->mu,dt,
                      blk->output_dir,err_message);
  }

  io_line_output_sac(ioline,dt,wav->cmp_name,blk->output_dir);

  //-------------------------------------------------------------------------------
  //-- postprocess
  //-------------------------------------------------------------------------------

  MPI_Finalize();

  return 0;
}
