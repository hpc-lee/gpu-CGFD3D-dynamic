/*********************************************************************
 * setup fd operators
 **********************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <mpi.h>

#include "fdlib_mem.h"
#include "fdlib_math.h"
#include "blk_t.h"
#include "cuda_common.h"

int
blk_init(blk_t *blk,
         const int myid)
{
  int ierr = 0;

  // alloc struct vars
  blk->fd         = (fd_t         *) malloc(sizeof(fd_t));
  blk->mympi      = (mympi_t      *) malloc(sizeof(mympi_t));
  blk->gd         = (gd_t         *) malloc(sizeof(gd_t));
  blk->gd_metric  = (gd_metric_t  *) malloc(sizeof(gd_metric_t));
  blk->md         = (md_t         *) malloc(sizeof(md_t));
  blk->wav        = (wav_t        *) malloc(sizeof(wav_t));
  blk->bdryfree   = (bdryfree_t   *) malloc(sizeof(bdryfree_t));
  blk->bdrypml    = (bdrypml_t    *) malloc(sizeof(bdrypml_t));
  blk->bdryexp    = (bdryexp_t    *) malloc(sizeof(bdryexp_t));
  blk->iorecv     = (iorecv_t     *) malloc(sizeof(iorecv_t));
  blk->ioline     = (ioline_t     *) malloc(sizeof(ioline_t));
  blk->iofault    = (iofault_t    *) malloc(sizeof(iofault_t));
  blk->ioslice    = (ioslice_t    *) malloc(sizeof(ioslice_t));
  blk->iosnap     = (iosnap_t     *) malloc(sizeof(iosnap_t));
  blk->fault      = (fault_t      *) malloc(sizeof(fault_t));
  blk->fault_coef = (fault_coef_t *) malloc(sizeof(fault_coef_t));
  blk->fault_wav  = (fault_wav_t  *) malloc(sizeof(fault_wav_t));
  blk->io_fault_recv = (io_fault_recv_t *) malloc(sizeof(io_fault_recv_t));

  sprintf(blk->name, "%s", "single");

  return ierr;
}

// set str
int
blk_set_output(blk_t *blk,
               mympi_t *mympi,
               char *output_dir,
               char *grid_export_dir,
               char *media_export_dir)
{
  // output name
  sprintf(blk->output_fname_part,"px%d_py%d_pz%d", mympi->topoid[0],mympi->topoid[1],mympi->topoid[2]);

  // output
  sprintf(blk->output_dir, "%s", output_dir);
  sprintf(blk->grid_export_dir, "%s", grid_export_dir);
  sprintf(blk->media_export_dir, "%s", media_export_dir);

  return 0;
}


/*********************************************************************
 * estimate dt
 *********************************************************************/

int
blk_dt_esti_curv(gd_t *gd, md_t *md,
    float CFL, float *dtmax, float *dtmaxVp, float *dtmaxL,
    int *dtmaxi, int *dtmaxj, int *dtmaxk)
{
  int ierr = 0;

  float dtmax_local = 1.0e10;
  float Vp;

  float *x3d = gd->x3d;
  float *y3d = gd->y3d;
  float *z3d = gd->z3d;

  for (int k = gd->nk1; k <= gd->nk2; k++)
  {
    for (int j = gd->nj1; j <= gd->nj2; j++)
    {
      for (int i = gd->ni1; i <= gd->ni2; i++)
      {
        size_t iptr = i + j * gd->siz_iy + k * gd->siz_iz;

        if (md->medium_type == CONST_MEDIUM_ELASTIC_ISO) {
          Vp = sqrt( (md->lambda[iptr] + 2.0 * md->mu[iptr]) / md->rho[iptr] );
        } else if (md->medium_type == CONST_MEDIUM_ELASTIC_VTI) {
          float Vpv = sqrt( md->c33[iptr] / md->rho[iptr] );
          float Vph = sqrt( md->c11[iptr] / md->rho[iptr] );
          Vp = Vph > Vpv ? Vph : Vpv;
        } else if (md->medium_type == CONST_MEDIUM_ELASTIC_ANISO) {
          // need to implement accurate solution
          Vp = sqrt( md->c11[iptr] / md->rho[iptr] );
        } else if (md->medium_type == CONST_MEDIUM_ACOUSTIC_ISO) {
          Vp = sqrt( md->kappa[iptr] / md->rho[iptr] );
        }

        float dtLe = 1.0e20;
        float p0[] = { x3d[iptr], y3d[iptr], z3d[iptr] };

        // min L to 8 adjacent planes
        for (int kk = -1; kk <=1; kk++) {
          for (int jj = -1; jj <= 1; jj++) {
            for (int ii = -1; ii <= 1; ii++) {
              if (ii != 0 && jj !=0 && kk != 0)
              {
                float p1[] = { x3d[iptr-ii], y3d[iptr-ii], z3d[iptr-ii] };
                float p2[] = { x3d[iptr-jj*gd->siz_iy],
                               y3d[iptr-jj*gd->siz_iy],
                               z3d[iptr-jj*gd->siz_iy] };
                float p3[] = { x3d[iptr-kk*gd->siz_iz],
                               y3d[iptr-kk*gd->siz_iz],
                               z3d[iptr-kk*gd->siz_iz] };

                float L = fdlib_math_dist_point2plane(p0, p1, p2, p3);

                if (dtLe > L) dtLe = L;
              }
            }
          }
        }

        // convert to dt
        float dt_point = CFL / Vp * dtLe;

        // if smaller
        if (dt_point < dtmax_local) {
          dtmax_local = dt_point;
          *dtmaxi = i;
          *dtmaxj = j;
          *dtmaxk = k;
          *dtmaxVp = Vp;
          *dtmaxL  = dtLe;
        }

      } // i
    } // i
  } //k

  *dtmax = dtmax_local;

  return ierr;
}

float
blk_keep_three_digi(float dt)
{
  char str[40];
  float dt_2;

  sprintf(str, "%9.7e", dt);

  for (int i = 3; i < 9; i++)
    str[i] = '0';

  sscanf(str, "%f", &dt_2);
  
  return dt_2;
}

/*********************************************************************
 * mpi message for macdrp scheme with rk
 *********************************************************************/

int
macdrp_mesg_init(mympi_t *mympi,
                 fd_t *fd,
                 int ni,
                 int nj,
                 int nk,
                 int num_of_vars)
{
  // alloc
  mympi->pair_siz_sbuff_y1 = (size_t **)malloc(fd->num_of_pairs * sizeof(size_t *));
  mympi->pair_siz_sbuff_y2 = (size_t **)malloc(fd->num_of_pairs * sizeof(size_t *));
  mympi->pair_siz_sbuff_z1 = (size_t **)malloc(fd->num_of_pairs * sizeof(size_t *));
  mympi->pair_siz_sbuff_z2 = (size_t **)malloc(fd->num_of_pairs * sizeof(size_t *));

  mympi->pair_siz_rbuff_y1 = (size_t **)malloc(fd->num_of_pairs * sizeof(size_t *));
  mympi->pair_siz_rbuff_y2 = (size_t **)malloc(fd->num_of_pairs * sizeof(size_t *));
  mympi->pair_siz_rbuff_z1 = (size_t **)malloc(fd->num_of_pairs * sizeof(size_t *));
  mympi->pair_siz_rbuff_z2 = (size_t **)malloc(fd->num_of_pairs * sizeof(size_t *));

  mympi->pair_s_reqs       = (MPI_Request ***)malloc(fd->num_of_pairs * sizeof(MPI_Request **));
  mympi->pair_r_reqs       = (MPI_Request ***)malloc(fd->num_of_pairs * sizeof(MPI_Request **));
  for (int ipair = 0; ipair < fd->num_of_pairs; ipair++)
  {
    mympi->pair_siz_sbuff_y1[ipair] = (size_t *)malloc(fd->num_rk_stages * sizeof(size_t));
    mympi->pair_siz_sbuff_y2[ipair] = (size_t *)malloc(fd->num_rk_stages * sizeof(size_t));
    mympi->pair_siz_sbuff_z1[ipair] = (size_t *)malloc(fd->num_rk_stages * sizeof(size_t));
    mympi->pair_siz_sbuff_z2[ipair] = (size_t *)malloc(fd->num_rk_stages * sizeof(size_t));

    mympi->pair_siz_rbuff_y1[ipair] = (size_t *)malloc(fd->num_rk_stages * sizeof(size_t));
    mympi->pair_siz_rbuff_y2[ipair] = (size_t *)malloc(fd->num_rk_stages * sizeof(size_t));
    mympi->pair_siz_rbuff_z1[ipair] = (size_t *)malloc(fd->num_rk_stages * sizeof(size_t));
    mympi->pair_siz_rbuff_z2[ipair] = (size_t *)malloc(fd->num_rk_stages * sizeof(size_t));

    mympi->pair_s_reqs[ipair] = (MPI_Request **)malloc(fd->num_rk_stages * sizeof(MPI_Request *));
    mympi->pair_r_reqs[ipair] = (MPI_Request **)malloc(fd->num_rk_stages * sizeof(MPI_Request *));

    for (int istage = 0; istage < fd->num_rk_stages; istage++)
    {
      mympi->pair_s_reqs[ipair][istage] = (MPI_Request *)malloc(4 * sizeof(MPI_Request));
      mympi->pair_r_reqs[ipair][istage] = (MPI_Request *)malloc(4 * sizeof(MPI_Request));
    }
  }

  // mpi mesg
  mympi->siz_sbuff = 0;
  mympi->siz_rbuff = 0;
  for (int ipair = 0; ipair < fd->num_of_pairs; ipair++)
  {
    for (int istage = 0; istage < fd->num_rk_stages; istage++)
    {
      fd_op_t *fdy_op = fd->pair_fdy_op[ipair][istage];
      fd_op_t *fdz_op = fd->pair_fdz_op[ipair][istage];

      // wave exchange
      // y1 side, depends on right_len of y1 proc
      mympi->pair_siz_sbuff_y1[ipair][istage] = (ni * nk * fdy_op->right_len) * num_of_vars;
      // y2 side, depends on left_len of y2 proc
      mympi->pair_siz_sbuff_y2[ipair][istage] = (ni * nk * fdy_op->left_len ) * num_of_vars;

      mympi->pair_siz_sbuff_z1[ipair][istage] = (ni * nj * fdz_op->right_len) * num_of_vars;
      mympi->pair_siz_sbuff_z2[ipair][istage] = (ni * nj * fdz_op->left_len ) * num_of_vars;

      // y1 side, depends on left_len of cur proc
      mympi->pair_siz_rbuff_y1[ipair][istage] = (ni * nk * fdy_op->left_len ) * num_of_vars;
      // y2 side, depends on right_len of cur proc
      mympi->pair_siz_rbuff_y2[ipair][istage] = (ni * nk * fdy_op->right_len) * num_of_vars;

      mympi->pair_siz_rbuff_z1[ipair][istage] = (ni * nj * fdz_op->left_len ) * num_of_vars;
      mympi->pair_siz_rbuff_z2[ipair][istage] = (ni * nj * fdz_op->right_len) * num_of_vars;

      size_t siz_s =  mympi->pair_siz_sbuff_y1[ipair][istage]
                    + mympi->pair_siz_sbuff_y2[ipair][istage]
                    + mympi->pair_siz_sbuff_z1[ipair][istage]
                    + mympi->pair_siz_sbuff_z2[ipair][istage];

      size_t siz_r =  mympi->pair_siz_rbuff_y1[ipair][istage]
                    + mympi->pair_siz_rbuff_y2[ipair][istage]
                    + mympi->pair_siz_rbuff_z1[ipair][istage]
                    + mympi->pair_siz_rbuff_z2[ipair][istage];

      if (siz_s > mympi->siz_sbuff) mympi->siz_sbuff = siz_s;
      if (siz_r > mympi->siz_rbuff) mympi->siz_rbuff = siz_r;
    }
  }
  // alloc in gpu
  mympi->sbuff = (float *) cuda_malloc(mympi->siz_sbuff * sizeof(MPI_FLOAT));
  mympi->rbuff = (float *) cuda_malloc(mympi->siz_rbuff * sizeof(MPI_FLOAT));

  // set up pers communication
  for (int ipair = 0; ipair < fd->num_of_pairs; ipair++)
  {
    for (int istage = 0; istage < fd->num_rk_stages; istage++)
    {
      size_t siz_s_y1 = mympi->pair_siz_sbuff_y1[ipair][istage];
      size_t siz_s_y2 = mympi->pair_siz_sbuff_y2[ipair][istage];
      size_t siz_s_z1 = mympi->pair_siz_sbuff_z1[ipair][istage];
      size_t siz_s_z2 = mympi->pair_siz_sbuff_z2[ipair][istage];

      float *sbuff_y1 = mympi->sbuff;
      float *sbuff_y2 = sbuff_y1 + siz_s_y1;
      float *sbuff_z1 = sbuff_y2 + siz_s_y2;
      float *sbuff_z2 = sbuff_z1 + siz_s_z1;
      
      // npair: xx, nstage: x, 
      int tag_pair_stage = ipair * 1000 + istage * 100;
      int tag[4] = { tag_pair_stage+21, tag_pair_stage+22, tag_pair_stage+31, tag_pair_stage+32}; 

      // send
      MPI_Send_init(sbuff_y1, siz_s_y1, MPI_FLOAT, mympi->neighid[2], tag[0], mympi->topocomm, &(mympi->pair_s_reqs[ipair][istage][0]));
      MPI_Send_init(sbuff_y2, siz_s_y2, MPI_FLOAT, mympi->neighid[3], tag[1], mympi->topocomm, &(mympi->pair_s_reqs[ipair][istage][1]));
      MPI_Send_init(sbuff_z1, siz_s_z1, MPI_FLOAT, mympi->neighid[4], tag[2], mympi->topocomm, &(mympi->pair_s_reqs[ipair][istage][2]));
      MPI_Send_init(sbuff_z2, siz_s_z2, MPI_FLOAT, mympi->neighid[5], tag[3], mympi->topocomm, &(mympi->pair_s_reqs[ipair][istage][3]));

      // recv
      size_t siz_r_y1 = mympi->pair_siz_rbuff_y1[ipair][istage];
      size_t siz_r_y2 = mympi->pair_siz_rbuff_y2[ipair][istage];
      size_t siz_r_z1 = mympi->pair_siz_rbuff_z1[ipair][istage];
      size_t siz_r_z2 = mympi->pair_siz_rbuff_z2[ipair][istage];

      float *rbuff_y1 = mympi->rbuff;
      float *rbuff_y2 = rbuff_y1 + siz_r_y1;
      float *rbuff_z1 = rbuff_y2 + siz_r_y2;
      float *rbuff_z2 = rbuff_z1 + siz_r_z1;

      // recv
      MPI_Recv_init(rbuff_y1, siz_r_y1, MPI_FLOAT, mympi->neighid[2], tag[1], mympi->topocomm, &(mympi->pair_r_reqs[ipair][istage][0]));
      MPI_Recv_init(rbuff_y2, siz_r_y2, MPI_FLOAT, mympi->neighid[3], tag[0], mympi->topocomm, &(mympi->pair_r_reqs[ipair][istage][1]));
      MPI_Recv_init(rbuff_z1, siz_r_z1, MPI_FLOAT, mympi->neighid[4], tag[3], mympi->topocomm, &(mympi->pair_r_reqs[ipair][istage][2]));
      MPI_Recv_init(rbuff_z2, siz_r_z2, MPI_FLOAT, mympi->neighid[5], tag[2], mympi->topocomm, &(mympi->pair_r_reqs[ipair][istage][3]));
    }
  }

  return 0;
}

int
macdrp_fault_mesg_init(mympi_t *mympi,
                       fd_t *fd,
                       int nj,
                       int nk,
                       int num_of_vars_fault,
                       int number_fault)
{
  // alloc
  mympi->pair_siz_sbuff_y1_fault = (size_t **)malloc(fd->num_of_pairs * sizeof(size_t *));
  mympi->pair_siz_sbuff_y2_fault = (size_t **)malloc(fd->num_of_pairs * sizeof(size_t *));
  mympi->pair_siz_sbuff_z1_fault = (size_t **)malloc(fd->num_of_pairs * sizeof(size_t *));
  mympi->pair_siz_sbuff_z2_fault = (size_t **)malloc(fd->num_of_pairs * sizeof(size_t *));

  mympi->pair_siz_rbuff_y1_fault = (size_t **)malloc(fd->num_of_pairs * sizeof(size_t *));
  mympi->pair_siz_rbuff_y2_fault = (size_t **)malloc(fd->num_of_pairs * sizeof(size_t *));
  mympi->pair_siz_rbuff_z1_fault = (size_t **)malloc(fd->num_of_pairs * sizeof(size_t *));
  mympi->pair_siz_rbuff_z2_fault = (size_t **)malloc(fd->num_of_pairs * sizeof(size_t *));

  mympi->pair_s_reqs_fault       = (MPI_Request ***)malloc(fd->num_of_pairs * sizeof(MPI_Request **));
  mympi->pair_r_reqs_fault       = (MPI_Request ***)malloc(fd->num_of_pairs * sizeof(MPI_Request **));

  for (int ipair = 0; ipair < fd->num_of_pairs; ipair++)
  {
    mympi->pair_siz_sbuff_y1_fault[ipair] = (size_t *)malloc(fd->num_rk_stages * sizeof(size_t));
    mympi->pair_siz_sbuff_y2_fault[ipair] = (size_t *)malloc(fd->num_rk_stages * sizeof(size_t));
    mympi->pair_siz_sbuff_z1_fault[ipair] = (size_t *)malloc(fd->num_rk_stages * sizeof(size_t));
    mympi->pair_siz_sbuff_z2_fault[ipair] = (size_t *)malloc(fd->num_rk_stages * sizeof(size_t));

    mympi->pair_siz_rbuff_y1_fault[ipair] = (size_t *)malloc(fd->num_rk_stages * sizeof(size_t));
    mympi->pair_siz_rbuff_y2_fault[ipair] = (size_t *)malloc(fd->num_rk_stages * sizeof(size_t));
    mympi->pair_siz_rbuff_z1_fault[ipair] = (size_t *)malloc(fd->num_rk_stages * sizeof(size_t));
    mympi->pair_siz_rbuff_z2_fault[ipair] = (size_t *)malloc(fd->num_rk_stages * sizeof(size_t));
    mympi->pair_s_reqs_fault[ipair] = (MPI_Request **)malloc(fd->num_rk_stages * sizeof(MPI_Request *));
    mympi->pair_r_reqs_fault[ipair] = (MPI_Request **)malloc(fd->num_rk_stages * sizeof(MPI_Request *));

    for (int istage = 0; istage < fd->num_rk_stages; istage++)
    {
      mympi->pair_s_reqs_fault[ipair][istage] = (MPI_Request *)malloc(4 * sizeof(MPI_Request));
      mympi->pair_r_reqs_fault[ipair][istage] = (MPI_Request *)malloc(4 * sizeof(MPI_Request));
    }
  }

  // mpi mesg
  mympi->siz_sbuff_fault = 0;
  mympi->siz_rbuff_fault = 0;
  for (int ipair = 0; ipair < fd->num_of_pairs; ipair++)
  {
    for (int istage = 0; istage < fd->num_rk_stages; istage++)
    {
      fd_op_t *fdy_op = fd->pair_fdy_op[ipair][istage];
      fd_op_t *fdz_op = fd->pair_fdz_op[ipair][istage];
      // fault wave exchange
      // minus and plus, multiply 2
      mympi->pair_siz_sbuff_y1_fault[ipair][istage] = (nk * fdy_op->right_len) * 2 * num_of_vars_fault * number_fault;
      mympi->pair_siz_sbuff_y2_fault[ipair][istage] = (nk * fdy_op->left_len ) * 2 * num_of_vars_fault * number_fault;

      mympi->pair_siz_sbuff_z1_fault[ipair][istage] = (nj * fdz_op->right_len) * 2 *  num_of_vars_fault * number_fault;
      mympi->pair_siz_sbuff_z2_fault[ipair][istage] = (nj * fdz_op->left_len ) * 2 *  num_of_vars_fault * number_fault;

      mympi->pair_siz_rbuff_y1_fault[ipair][istage] = (nk * fdy_op->left_len ) * 2 * num_of_vars_fault * number_fault;
      mympi->pair_siz_rbuff_y2_fault[ipair][istage] = (nk * fdy_op->right_len) * 2 * num_of_vars_fault * number_fault;

      mympi->pair_siz_rbuff_z1_fault[ipair][istage] = (nj * fdz_op->left_len ) * 2 * num_of_vars_fault * number_fault;
      mympi->pair_siz_rbuff_z2_fault[ipair][istage] = (nj * fdz_op->right_len) * 2 * num_of_vars_fault * number_fault;

      size_t siz_s =  mympi->pair_siz_sbuff_y1_fault[ipair][istage]
                   +  mympi->pair_siz_sbuff_y2_fault[ipair][istage]
                   +  mympi->pair_siz_sbuff_z1_fault[ipair][istage]
                   +  mympi->pair_siz_sbuff_z2_fault[ipair][istage];

       size_t siz_r = mympi->pair_siz_rbuff_y1_fault[ipair][istage]
                    + mympi->pair_siz_rbuff_y2_fault[ipair][istage]
                    + mympi->pair_siz_rbuff_z1_fault[ipair][istage]
                    + mympi->pair_siz_rbuff_z2_fault[ipair][istage];

      if (siz_s > mympi->siz_sbuff_fault) mympi->siz_sbuff_fault = siz_s;
      if (siz_r > mympi->siz_rbuff_fault) mympi->siz_rbuff_fault = siz_r;
    }
  }
  // alloc in gpu
  mympi->sbuff_fault = (float *) cuda_malloc(mympi->siz_sbuff_fault * sizeof(MPI_FLOAT));
  mympi->rbuff_fault = (float *) cuda_malloc(mympi->siz_rbuff_fault * sizeof(MPI_FLOAT));

  // set up pers communication
  for (int ipair = 0; ipair < fd->num_of_pairs; ipair++)
  {
    for (int istage = 0; istage < fd->num_rk_stages; istage++)
    {
      size_t siz_s_y1_fault = mympi->pair_siz_sbuff_y1_fault[ipair][istage];
      size_t siz_s_y2_fault = mympi->pair_siz_sbuff_y2_fault[ipair][istage];
      size_t siz_s_z1_fault = mympi->pair_siz_sbuff_z1_fault[ipair][istage];
      size_t siz_s_z2_fault = mympi->pair_siz_sbuff_z2_fault[ipair][istage];

      float *sbuff_y1_fault = mympi->sbuff_fault;
      float *sbuff_y2_fault = sbuff_y1_fault + siz_s_y1_fault;
      float *sbuff_z1_fault = sbuff_y2_fault + siz_s_y2_fault;
      float *sbuff_z2_fault = sbuff_z1_fault + siz_s_z1_fault;

      // npair: xx, nstage: x, 
      int tag_pair_stage = ipair * 1000 + istage * 100;
      int tag[4] = { tag_pair_stage+210, tag_pair_stage+220, tag_pair_stage+310, tag_pair_stage+320}; 

      // send
      MPI_Send_init(sbuff_y1_fault, siz_s_y1_fault, MPI_FLOAT, mympi->neighid[2], tag[0], mympi->topocomm, &(mympi->pair_s_reqs_fault[ipair][istage][0]));
      MPI_Send_init(sbuff_y2_fault, siz_s_y2_fault, MPI_FLOAT, mympi->neighid[3], tag[1], mympi->topocomm, &(mympi->pair_s_reqs_fault[ipair][istage][1]));
      MPI_Send_init(sbuff_z1_fault, siz_s_z1_fault, MPI_FLOAT, mympi->neighid[4], tag[2], mympi->topocomm, &(mympi->pair_s_reqs_fault[ipair][istage][2]));
      MPI_Send_init(sbuff_z2_fault, siz_s_z2_fault, MPI_FLOAT, mympi->neighid[5], tag[3], mympi->topocomm, &(mympi->pair_s_reqs_fault[ipair][istage][3]));

      size_t siz_r_y1_fault = mympi->pair_siz_rbuff_y1_fault[ipair][istage];
      size_t siz_r_y2_fault = mympi->pair_siz_rbuff_y2_fault[ipair][istage];
      size_t siz_r_z1_fault = mympi->pair_siz_rbuff_z1_fault[ipair][istage];
      size_t siz_r_z2_fault = mympi->pair_siz_rbuff_z2_fault[ipair][istage];

      float *rbuff_y1_fault = mympi->rbuff_fault;
      float *rbuff_y2_fault = rbuff_y1_fault + siz_r_y1_fault;
      float *rbuff_z1_fault = rbuff_y2_fault + siz_r_y2_fault;
      float *rbuff_z2_fault = rbuff_z1_fault + siz_r_z1_fault;

      //recv
      MPI_Recv_init(rbuff_y1_fault, siz_r_y1_fault, MPI_FLOAT, mympi->neighid[2], tag[1], mympi->topocomm, &(mympi->pair_r_reqs_fault[ipair][istage][0]));
      MPI_Recv_init(rbuff_y2_fault, siz_r_y2_fault, MPI_FLOAT, mympi->neighid[3], tag[0], mympi->topocomm, &(mympi->pair_r_reqs_fault[ipair][istage][1]));
      MPI_Recv_init(rbuff_z1_fault, siz_r_z1_fault, MPI_FLOAT, mympi->neighid[4], tag[3], mympi->topocomm, &(mympi->pair_r_reqs_fault[ipair][istage][2]));
      MPI_Recv_init(rbuff_z2_fault, siz_r_z2_fault, MPI_FLOAT, mympi->neighid[5], tag[2], mympi->topocomm, &(mympi->pair_r_reqs_fault[ipair][istage][3]));
    }
  }

  return 0;
}


int 
macdrp_pack_mesg_gpu(float * w_cur,
                     fd_t *fd,
                     gd_t *gd, 
                     mympi_t *mympi, 
                     int ipair_mpi,
                     int istage_mpi,
                     int num_of_vars,
                     int myid)
{
  int ni1 = gd->ni1;
  int ni2 = gd->ni2;
  int nj1 = gd->nj1;
  int nj2 = gd->nj2;
  int nk1 = gd->nk1;
  int nk2 = gd->nk2;
  size_t siz_iy  = gd->siz_iy;
  size_t siz_iz  = gd->siz_iz;
  size_t siz_icmp = gd->siz_icmp;
  int ni = gd->ni;
  int nj = gd->nj;
  int nk = gd->nk;

  fd_op_t *fdy_op = fd->pair_fdy_op[ipair_mpi][istage_mpi];
  fd_op_t *fdz_op = fd->pair_fdz_op[ipair_mpi][istage_mpi];
  // ghost point
  int ny1_g = fdy_op->right_len;
  int ny2_g = fdy_op->left_len;
  int nz1_g = fdz_op->right_len;
  int nz2_g = fdz_op->left_len;
  size_t siz_sbuff_y1 = mympi->pair_siz_sbuff_y1[ipair_mpi][istage_mpi];
  size_t siz_sbuff_y2 = mympi->pair_siz_sbuff_y2[ipair_mpi][istage_mpi];
  size_t siz_sbuff_z1 = mympi->pair_siz_sbuff_z1[ipair_mpi][istage_mpi];
  
  float *sbuff_y1 = mympi->sbuff;
  float *sbuff_y2 = sbuff_y1 + siz_sbuff_y1;
  float *sbuff_z1 = sbuff_y2 + siz_sbuff_y2;
  float *sbuff_z2 = sbuff_z1 + siz_sbuff_z1;
  {
    dim3 block(8,ny1_g,8);
    dim3 grid;
    grid.x = (ni + block.x - 1) / block.x;
    grid.y = (ny1_g + block.y -1) / block.y;
    grid.z = (nk + block.z - 1) / block.z;
    macdrp_pack_mesg_y1<<<grid, block >>>(
           w_cur, sbuff_y1, siz_iy, siz_iz, siz_icmp, num_of_vars,
           ni1, nj1, nk1, ni, ny1_g, nk);
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(8,ny2_g,8);
    dim3 grid;
    grid.x = (ni + block.x - 1) / block.x;
    grid.y = (ny2_g + block.y -1) / block.y;
    grid.z = (nk + block.z - 1) / block.z;
    macdrp_pack_mesg_y2<<<grid, block >>>(
           w_cur, sbuff_y2, siz_iy, siz_iz, siz_icmp,
           num_of_vars, ni1, nj2, nk1, ni, ny2_g, nk);
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(8,8,nz1_g);
    dim3 grid;
    grid.x = (ni + block.x - 1) / block.x;
    grid.y = (nj + block.y - 1) / block.y;
    grid.z = (nz1_g + block.z - 1) / block.z;
    macdrp_pack_mesg_z1<<<grid, block >>>(
           w_cur, sbuff_z1, siz_iy, siz_iz, siz_icmp,
           num_of_vars, ni1, nj1, nk1, ni, nj, nz1_g);
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(8,8,nz2_g);
    dim3 grid;
    grid.x = (ni + block.x - 1) / block.x;
    grid.y = (nj + block.y - 1) / block.y;
    grid.z = (nz2_g + block.z - 1) / block.z;
    macdrp_pack_mesg_z2<<<grid, block >>>(
           w_cur, sbuff_z2, siz_iy, siz_iz, siz_icmp,
           num_of_vars, ni1, nj1, nk2, ni, nj, nz2_g);
    CUDACHECK(cudaDeviceSynchronize());
  }

  return 0;
}

__global__ void
macdrp_pack_mesg_y1(
           float *w_cur, float *sbuff_y1, size_t siz_iy, size_t siz_iz, size_t siz_icmp,
           int num_of_vars, int ni1, int nj1, int nk1, int ni, int ny1_g, int nk)
{
  int ix = blockIdx.x * blockDim.x + threadIdx.x;
  int iy = blockIdx.y * blockDim.y + threadIdx.y;
  int iz = blockIdx.z * blockDim.z + threadIdx.z;
  size_t iptr_b;
  size_t iptr;
  if(ix<ni && iy<ny1_g && iz<nk)
  {
    iptr     = (iz+nk1) * siz_iz + (iy+nj1) * siz_iy + (ix+ni1);
    iptr_b   = iz*ni*ny1_g + iy*ni + ix;
    for(int i=0; i<num_of_vars; i++)
    {
      sbuff_y1[iptr_b + i*ny1_g*ni*nk] = w_cur[iptr + i*siz_icmp];
    }
  }

  return;
}

__global__ void
macdrp_pack_mesg_y2(
           float *w_cur, float *sbuff_y2, size_t siz_iy, size_t siz_iz, size_t siz_icmp,
           int num_of_vars, int ni1, int nj2, int nk1, int ni, int ny2_g, int nk)
{
  int ix = blockIdx.x * blockDim.x + threadIdx.x;
  int iy = blockIdx.y * blockDim.y + threadIdx.y;
  int iz = blockIdx.z * blockDim.z + threadIdx.z;
  size_t iptr_b;
  size_t iptr;
  if(ix<ni && iy<ny2_g && iz<nk)
  {
    iptr     = (iz+nk1) * siz_iz + (iy+nj2-ny2_g+1) * siz_iy + (ix+ni1);
    iptr_b   = iz*ni*ny2_g + iy*ni + ix;
    for(int i=0; i<num_of_vars; i++)
    {
      sbuff_y2[iptr_b + i*ny2_g*ni*nk] = w_cur[iptr + i*siz_icmp];
    }
  }
  return;
}

__global__ void
macdrp_pack_mesg_z1(
           float *w_cur, float *sbuff_z1, size_t siz_iy, size_t siz_iz, size_t siz_icmp,
           int num_of_vars, int ni1, int nj1, int nk1, int ni, int nj, int nz1_g)
{
  int ix = blockIdx.x * blockDim.x + threadIdx.x;
  int iy = blockIdx.y * blockDim.y + threadIdx.y;
  int iz = blockIdx.z * blockDim.z + threadIdx.z;
  size_t iptr_b;
  size_t iptr;
  if(ix<ni && iy<nj && iz<nz1_g)
  {
    iptr     = (iz+nk1) * siz_iz+ (iy+nj1) * siz_iy + (ix+ni1);
    iptr_b   = iz*ni*nj + iy*ni + ix;
    for(int i=0; i<num_of_vars; i++)
    {
      sbuff_z1[iptr_b + i*nz1_g*ni*nj] = w_cur[iptr + i*siz_icmp];
    }
  }
  return;
}

__global__ void
macdrp_pack_mesg_z2(
           float *w_cur, float *sbuff_z2, size_t siz_iy, size_t siz_iz, size_t siz_icmp,
           int num_of_vars, int ni1, int nj1, int nk2, int ni, int nj, int nz2_g)
{
  int ix = blockIdx.x * blockDim.x + threadIdx.x;
  int iy = blockIdx.y * blockDim.y + threadIdx.y;
  int iz = blockIdx.z * blockDim.z + threadIdx.z;
  size_t iptr_b;
  size_t iptr;
  if(ix<ni && iy<nj && iz<nz2_g)
  {
    iptr     = (iz+nk2-nz2_g+1) * siz_iz + (iy+nj1) * siz_iy + (ix+ni1);
    iptr_b   = iz*ni*nj + iy*ni + ix;
    for(int i=0; i<num_of_vars; i++)
    {
      sbuff_z2[iptr_b + i*nz2_g*ni*nj] = w_cur[iptr + i*siz_icmp];
    }
  }
  return;
}

int 
macdrp_unpack_mesg_gpu(float *w_cur, 
                       fd_t *fd,
                       gd_t *gd,
                       mympi_t *mympi, 
                       int ipair_mpi,
                       int istage_mpi,
                       int num_of_vars,
                       int *neighid)
{
  int ni1 = gd->ni1;
  int ni2 = gd->ni2;
  int nj1 = gd->nj1;
  int nj2 = gd->nj2;
  int nk1 = gd->nk1;
  int nk2 = gd->nk2;
  size_t siz_iy  = gd->siz_iy;
  size_t siz_iz  = gd->siz_iz;
  size_t siz_icmp = gd->siz_icmp;

  int ni = gd->ni;
  int nj = gd->nj;
  int nk = gd->nk;
  
  fd_op_t *fdy_op = fd->pair_fdy_op[ipair_mpi][istage_mpi];
  fd_op_t *fdz_op = fd->pair_fdz_op[ipair_mpi][istage_mpi];
  // ghost point
  int ny1_g = fdy_op->right_len;
  int ny2_g = fdy_op->left_len;
  int nz1_g = fdz_op->right_len;
  int nz2_g = fdz_op->left_len;

  size_t siz_rbuff_y1 = mympi->pair_siz_rbuff_y1[ipair_mpi][istage_mpi];
  size_t siz_rbuff_y2 = mympi->pair_siz_rbuff_y2[ipair_mpi][istage_mpi];
  size_t siz_rbuff_z1 = mympi->pair_siz_rbuff_z1[ipair_mpi][istage_mpi];

  float *rbuff_y1 = mympi->rbuff;
  float *rbuff_y2 = rbuff_y1 + siz_rbuff_y1;
  float *rbuff_z1 = rbuff_y2 + siz_rbuff_y2;
  float *rbuff_z2 = rbuff_z1 + siz_rbuff_z1;
  {
    dim3 block(8,ny2_g,8);
    dim3 grid;
    grid.x = (ni + block.x - 1) / block.x;
    grid.y = (ny2_g + block.y -1) / block.y;
    grid.z = (nk + block.z - 1) / block.z;
    macdrp_unpack_mesg_y1<<< grid, block >>>(
           w_cur, rbuff_y1, siz_iy, siz_iz, siz_icmp,
           num_of_vars, ni1, nj1, nk1, ni, ny2_g, nk, neighid);
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(8,ny1_g,8);
    dim3 grid;
    grid.x = (ni + block.x - 1) / block.x;
    grid.y = (ny1_g + block.y -1) / block.y;
    grid.z = (nk + block.z - 1) / block.z;
    macdrp_unpack_mesg_y2<<< grid, block >>>(
           w_cur, rbuff_y2, siz_iy, siz_iz, siz_icmp,
           num_of_vars, ni1, nj2, nk1, ni, ny1_g, nk, neighid);
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(8,8,nz2_g);
    dim3 grid;
    grid.x = (ni + block.x - 1) / block.x;
    grid.y = (nj + block.y -1) / block.y;
    grid.z = (nz2_g + block.z - 1) / block.z;
    macdrp_unpack_mesg_z1<<< grid, block >>>(
           w_cur, rbuff_z1, siz_iy, siz_iz, siz_icmp, 
           num_of_vars, ni1, ni1, nk1, ni, nj, nz2_g, neighid);
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(8,8,nz1_g);
    dim3 grid;
    grid.x = (ni + block.x - 1) / block.x;
    grid.y = (nj + block.y -1) / block.y;
    grid.z = (nz1_g + block.z - 1) / block.z;
    macdrp_unpack_mesg_z2<<< grid, block >>>(
           w_cur, rbuff_z2, siz_iy, siz_iz, siz_icmp, 
           num_of_vars, ni1, nj1, nk2, ni, nj, nz1_g, neighid);
    CUDACHECK(cudaDeviceSynchronize());
  }

  return 0;
}

//from y2
__global__ void
macdrp_unpack_mesg_y1(
           float *w_cur, float *rbuff_y1, size_t siz_iy, size_t siz_iz, size_t siz_icmp,
           int num_of_vars, int ni1, int nj1, int nk1, int ni, int ny2_g, int nk, int *neighid)
{
  int ix = blockIdx.x * blockDim.x + threadIdx.x;
  int iy = blockIdx.y * blockDim.y + threadIdx.y;
  int iz = blockIdx.z * blockDim.z + threadIdx.z;
  size_t iptr_b;
  size_t iptr;
  if (neighid[2] != MPI_PROC_NULL) {
    if(ix<ni && iy<ny2_g && iz<nk){
      iptr   = (iz+nk1) * siz_iz + (iy+nj1-ny2_g) * siz_iy + (ix+ni1);
      iptr_b = iz*ni*ny2_g + iy*ni + ix;
      for(int i=0; i<num_of_vars; i++)
      {
        w_cur[iptr + i*siz_icmp] = rbuff_y1[iptr_b+ i*ny2_g*ni*nk];
      }
    }
  }
  return;
}

//from y1
__global__ void
macdrp_unpack_mesg_y2(
           float *w_cur, float *rbuff_y2, size_t siz_iy, size_t siz_iz, size_t siz_icmp, 
           int num_of_vars, int ni1, int nj2, int nk1, int ni, int ny1_g, int nk, int *neighid)
{
  int ix = blockIdx.x * blockDim.x + threadIdx.x;
  int iy = blockIdx.y * blockDim.y + threadIdx.y;
  int iz = blockIdx.z * blockDim.z + threadIdx.z;
  size_t iptr_b;
  size_t iptr;
  if (neighid[3] != MPI_PROC_NULL) {
    if(ix<ni && iy<ny1_g && iz<nk){
      iptr   = (iz+nk1) * siz_iz + (iy+nj2+1) * siz_iy + (ix+ni1);
      iptr_b = iz*ni*ny1_g + iy*ni + ix;
      for(int i=0; i<num_of_vars; i++)
      {
        w_cur[iptr + i*siz_icmp] = rbuff_y2[iptr_b+ i*ny1_g*ni*nk];
      }
    }
  }
  return;
}

//from z2
__global__ void
macdrp_unpack_mesg_z1(
           float *w_cur, float *rbuff_z1, size_t siz_iy, size_t siz_iz, size_t siz_icmp, 
           int num_of_vars, int ni1, int nj1, int nk1, int ni, int nj, int nz2_g, int *neighid)
{
  int ix = blockIdx.x * blockDim.x + threadIdx.x;
  int iy = blockIdx.y * blockDim.y + threadIdx.y;
  int iz = blockIdx.z * blockDim.z + threadIdx.z;
  size_t iptr_b;
  size_t iptr;
  if (neighid[4] != MPI_PROC_NULL)
  {
    if(ix<ni && iy<nj && iz<nz2_g)
    {
      iptr   = (ix+ni1) + (iy+nj1) * siz_iy + (iz+nk1-nz2_g) * siz_iz;
      iptr_b = iz*ni*nj + iy*ni + ix;
      for(int i=0; i<num_of_vars; i++)
      {
        w_cur[iptr + i*siz_icmp] = rbuff_z1[iptr_b + i*nz2_g*ni*nj];
      }
    }
  }
  return;
}

//from z1
__global__ void
macdrp_unpack_mesg_z2(
           float *w_cur, float *rbuff_z2, size_t siz_iy, size_t siz_iz, size_t siz_icmp,
           int num_of_vars, int ni1, int nj1, int nk2, int ni, int nj, int nz1_g, int *neighid)
{
  int ix = blockIdx.x * blockDim.x + threadIdx.x;
  int iy = blockIdx.y * blockDim.y + threadIdx.y;
  int iz = blockIdx.z * blockDim.z + threadIdx.z;
  size_t iptr_b;
  size_t iptr;
  if (neighid[5] != MPI_PROC_NULL)
  {
    if(ix<ni && iy<nj && iz<nz1_g)
    {
      iptr   = (ix+ni1) + (iy+nj1) * siz_iy + (iz+nk2+1) * siz_iz;
      iptr_b = iz*ni*nj + iy*ni + ix;
      for(int i=0; i<num_of_vars; i++)
      {
        w_cur[iptr + i*siz_icmp] = rbuff_z2[iptr_b+ i*nz1_g*ni*nj];
      }
    }
  }

  return;
}

int 
macdrp_pack_fault_mesg_gpu(float * fw_cur,
                           fd_t *fd,
                           gd_t *gd, 
                           fault_wav_t FW_d,
                           mympi_t *mympi, 
                           int ipair_mpi,
                           int istage_mpi,
                           int myid)
{
  int nj1 = gd->nj1;
  int nj2 = gd->nj2;
  int nk1 = gd->nk1;
  int nk2 = gd->nk2;
  int nj = gd->nj;
  int nk = gd->nk;
  int ny = gd->ny;
  size_t siz_slice_yz = gd->siz_slice_yz;

  fd_op_t *fdy_op = fd->pair_fdy_op[ipair_mpi][istage_mpi];
  fd_op_t *fdz_op = fd->pair_fdz_op[ipair_mpi][istage_mpi];
  // ghost point
  int ny1_g = fdy_op->right_len;
  int ny2_g = fdy_op->left_len;
  int nz1_g = fdz_op->right_len;
  int nz2_g = fdz_op->left_len;
  size_t siz_sbuff_y1_fault = mympi->pair_siz_sbuff_y1_fault[ipair_mpi][istage_mpi];
  size_t siz_sbuff_y2_fault = mympi->pair_siz_sbuff_y2_fault[ipair_mpi][istage_mpi];
  size_t siz_sbuff_z1_fault = mympi->pair_siz_sbuff_z1_fault[ipair_mpi][istage_mpi];
  size_t siz_sbuff_z2_fault = mympi->pair_siz_sbuff_z2_fault[ipair_mpi][istage_mpi];

  float *sbuff_y1_fault = mympi->sbuff_fault;
  float *sbuff_y2_fault = sbuff_y1_fault + siz_sbuff_y1_fault;
  float *sbuff_z1_fault = sbuff_y2_fault + siz_sbuff_y2_fault;
  float *sbuff_z2_fault = sbuff_z1_fault + siz_sbuff_z1_fault;

  int ncmp = FW_d.ncmp;
  int number_fault = FW_d.number_fault;

  {
    dim3 block(ny1_g,8);
    dim3 grid;
    grid.x = (ny1_g + block.x -1) / block.x;
    grid.y = (nk + block.y - 1) / block.y;
    int size_y1 = siz_sbuff_y1_fault/number_fault; // int/int 
    for(int id=0; id<number_fault; id++)
    {
      // get one fault size
      float *fw_cur_thisone = fw_cur + id*FW_d.siz_ilevel;
      float *sbuff_y1_fault_thisone = sbuff_y1_fault + id*size_y1;
      macdrp_pack_fault_mesg_y1<<<grid, block >>>(
                                   fw_cur_thisone, sbuff_y1_fault_thisone, siz_slice_yz, 
                                   ncmp, ny, nj1, nk1, ny1_g, nk);
    }
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(ny2_g,8);
    dim3 grid;
    grid.x = (ny2_g + block.x -1) / block.x;
    grid.y = (nk + block.y - 1) / block.y;
    int size_y2 = siz_sbuff_y2_fault/number_fault; // int/int 
    for(int id=0; id<number_fault; id++)
    {
      // get one fault size
      float *fw_cur_thisone = fw_cur + id*FW_d.siz_ilevel;
      float *sbuff_y2_fault_thisone = sbuff_y2_fault + id*size_y2;
      macdrp_pack_fault_mesg_y2<<<grid, block >>>(
                                   fw_cur_thisone, sbuff_y2_fault_thisone, siz_slice_yz, 
                                   ncmp, ny, nj2, nk1, ny2_g, nk);
    }
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(8,nz1_g);
    dim3 grid;
    grid.x = (nj + block.x - 1) / block.x;
    grid.y = (nz1_g + block.y - 1) / block.y;
    int size_z1 = siz_sbuff_z1_fault/number_fault; // int/int 
    for(int id=0; id<number_fault; id++)
    {
      // get one fault size
      float *fw_cur_thisone = fw_cur + id*FW_d.siz_ilevel;
      float *sbuff_z1_fault_thisone = sbuff_z1_fault + id*size_z1;
      macdrp_pack_fault_mesg_z1<<<grid, block >>>(
                                   fw_cur_thisone, sbuff_z1_fault_thisone, siz_slice_yz, 
                                   ncmp, ny, nj1, nk1, nj, nz1_g);
    }
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(8,nz2_g);
    dim3 grid;
    grid.x = (nj + block.x - 1) / block.x;
    grid.y = (nz2_g + block.y - 1) / block.y;
    int size_z2 = siz_sbuff_z2_fault/number_fault; // int/int 
    for(int id=0; id<number_fault; id++)
    {
      // get one fault size
      float *fw_cur_thisone = fw_cur + id*FW_d.siz_ilevel;
      float *sbuff_z2_fault_thisone = sbuff_z2_fault + id*size_z2;
      macdrp_pack_fault_mesg_z2<<<grid, block >>>(
                                   fw_cur_thisone, sbuff_z2_fault_thisone, siz_slice_yz,
                                   ncmp, ny, nj1, nk2, nj, nz2_g);
    }
    CUDACHECK(cudaDeviceSynchronize());
  }

  return 0;
}

__global__ void
macdrp_pack_fault_mesg_y1(
             float *fw_cur, float *sbuff_y1_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj1, int nk1, int ny1_g, int nk)
{
  int iy = blockIdx.x * blockDim.x + threadIdx.x;
  int iz = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iptr_b;
  size_t iptr;
  if(iy<ny1_g && iz<nk)
  {
    iptr     = (iz+nk1) * ny + (iy+nj1);
    iptr_b   = iz*ny1_g + iy;
    for(int i=0; i<2*ncmp; i++)
    {
      sbuff_y1_fault[iptr_b + i*ny1_g*nk] = fw_cur[iptr + i*siz_slice_yz];
    }
  }

  return;
}

__global__ void
macdrp_pack_fault_mesg_y2(
             float *fw_cur, float *sbuff_y2_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj2, int nk1, int ny2_g, int nk)
{
  int iy = blockIdx.x * blockDim.x + threadIdx.x;
  int iz = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iptr_b;
  size_t iptr;
  if(iy<ny2_g && iz<nk)
  {
    iptr     = (iz+nk1) * ny + (iy+nj2-ny2_g+1);
    iptr_b   = iz*ny2_g + iy;
    for(int i=0; i<2*ncmp; i++)
    {
      sbuff_y2_fault[iptr_b + i*ny2_g*nk] = fw_cur[iptr + i*siz_slice_yz];
    }
  }

  return;
}

__global__ void
macdrp_pack_fault_mesg_z1(
             float *fw_cur, float *sbuff_z1_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj1, int nk1, int nj, int nz1_g)
{
  int iy = blockIdx.x * blockDim.x + threadIdx.x;
  int iz = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iptr_b;
  size_t iptr;
  if(iy<nj && iz<nz1_g)
  {
    iptr     = (iz+nk1) * ny + (iy+nj1);
    iptr_b   = iz*nj + iy;
    for(int i=0; i<2*ncmp; i++)
    {
      sbuff_z1_fault[iptr_b + i*nz1_g*nj] = fw_cur[iptr + i*siz_slice_yz];
    }
  }

  return;
}

__global__ void
macdrp_pack_fault_mesg_z2(
             float *fw_cur, float *sbuff_z2_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj1, int nk2, int nj, int nz2_g)
{
  int iy = blockIdx.x * blockDim.x + threadIdx.x;
  int iz = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iptr_b;
  size_t iptr;
  if(iy<nj && iz<nz2_g)
  {
    iptr     = (iz+nk2-nz2_g+1) * ny + (iy+nj1);
    iptr_b   = iz*nj + iy;
    for(int i=0; i<2*ncmp; i++)
    {
      sbuff_z2_fault[iptr_b + i*nz2_g*nj] = fw_cur[iptr + i*siz_slice_yz];
    }
  }

  return;
}

int 
macdrp_unpack_fault_mesg_gpu(float *fw_cur, 
                             fd_t *fd,
                             gd_t *gd,
                             fault_wav_t FW_d,
                             mympi_t *mympi, 
                             int ipair_mpi,
                             int istage_mpi,
                             int *neighid)
{
  int nj1 = gd->nj1;
  int nj2 = gd->nj2;
  int nk1 = gd->nk1;
  int nk2 = gd->nk2;
  int nj = gd->nj;
  int nk = gd->nk;
  int ny = gd->ny;
  size_t siz_slice_yz = gd->siz_slice_yz;
  
  fd_op_t *fdy_op = fd->pair_fdy_op[ipair_mpi][istage_mpi];
  fd_op_t *fdz_op = fd->pair_fdz_op[ipair_mpi][istage_mpi];
  // ghost point
  int ny1_g = fdy_op->right_len;
  int ny2_g = fdy_op->left_len;
  int nz1_g = fdz_op->right_len;
  int nz2_g = fdz_op->left_len;

  size_t siz_rbuff_y1_fault = mympi->pair_siz_rbuff_y1_fault[ipair_mpi][istage_mpi];
  size_t siz_rbuff_y2_fault = mympi->pair_siz_rbuff_y2_fault[ipair_mpi][istage_mpi];
  size_t siz_rbuff_z1_fault = mympi->pair_siz_rbuff_z1_fault[ipair_mpi][istage_mpi];
  size_t siz_rbuff_z2_fault = mympi->pair_siz_rbuff_z2_fault[ipair_mpi][istage_mpi];

  float *rbuff_y1_fault = mympi->rbuff_fault;
  float *rbuff_y2_fault = rbuff_y1_fault + siz_rbuff_y1_fault;
  float *rbuff_z1_fault = rbuff_y2_fault + siz_rbuff_y2_fault;
  float *rbuff_z2_fault = rbuff_z1_fault + siz_rbuff_z1_fault;

  int ncmp = FW_d.ncmp;
  int number_fault = FW_d.number_fault;
  {
    dim3 block(ny2_g,8);
    dim3 grid;
    grid.x = (ny2_g + block.x -1) / block.x;
    grid.y = (nk + block.y - 1) / block.y;
    int size_y1 = siz_rbuff_y1_fault/number_fault; // int/int 
    for(int id=0; id<number_fault; id++)
    {
      // get one fault size
      float *fw_cur_thisone = fw_cur + id*FW_d.siz_ilevel;
      float *rbuff_y1_fault_thisone = rbuff_y1_fault + id*size_y1;
      macdrp_unpack_fault_mesg_y1<<< grid, block >>>(
             fw_cur_thisone, rbuff_y1_fault_thisone, siz_slice_yz, 
             ncmp, ny, nj1, nk1, ny2_g, nk, neighid);
    }
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(ny1_g,8);
    dim3 grid;
    grid.x = (ny1_g + block.x -1) / block.x;
    grid.y = (nk + block.y - 1) / block.y;
    int size_y2 = siz_rbuff_y2_fault/number_fault; // int/int 
    for(int id=0; id<number_fault; id++)
    {
      // get one fault size
      float *fw_cur_thisone = fw_cur + id*FW_d.siz_ilevel;
      float *rbuff_y2_fault_thisone = rbuff_y2_fault + id*size_y2;
      macdrp_unpack_fault_mesg_y2<<< grid, block >>>(
             fw_cur_thisone, rbuff_y2_fault_thisone, siz_slice_yz,
             ncmp, ny, nj2, nk1, ny1_g, nk, neighid);
    }
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(8,nz2_g);
    dim3 grid;
    grid.x = (nj + block.x -1) / block.x;
    grid.y = (nz2_g + block.y - 1) / block.y;
    int size_z1 = siz_rbuff_z1_fault/number_fault; // int/int 
    for(int id=0; id<number_fault; id++)
    {
      // get one fault size
      float *fw_cur_thisone = fw_cur + id*FW_d.siz_ilevel;
      float *rbuff_z1_fault_thisone = rbuff_z1_fault + id*size_z1;
      macdrp_unpack_fault_mesg_z1<<< grid, block >>>(
             fw_cur_thisone, rbuff_z1_fault_thisone, siz_slice_yz, 
             ncmp, ny, nj1, nk1, nj, nz2_g, neighid);
    }
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(8,nz1_g);
    dim3 grid;
    grid.x = (nj + block.x -1) / block.x;
    grid.y = (nz1_g + block.y - 1) / block.y;
    int size_z2 = siz_rbuff_z2_fault/number_fault; // int/int 
    for(int id=0; id<number_fault; id++)
    {
      // get one fault size
      float *fw_cur_thisone = fw_cur + id*FW_d.siz_ilevel;
      float *rbuff_z2_fault_thisone = rbuff_z2_fault + id*size_z2;
      macdrp_unpack_fault_mesg_z2<<< grid, block >>>(
             fw_cur_thisone, rbuff_z2_fault_thisone, siz_slice_yz, 
             ncmp, ny, nj1, nk2, nj, nz1_g, neighid);
    }
    CUDACHECK(cudaDeviceSynchronize());
  }

  return 0;
}

__global__ void
macdrp_unpack_fault_mesg_y1(
           float *fw_cur, float *rbuff_y1_fault, size_t siz_slice_yz, 
           int num_of_vars, int ny, int nj1, int nk1, int ny2_g, int nk, int *neighid)
{
  int iy = blockIdx.x * blockDim.x + threadIdx.x;
  int iz = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iptr_b;
  size_t iptr;
  if (neighid[2] != MPI_PROC_NULL) {
    if(iy<ny2_g && iz<nk){
      iptr   = (iz+nk1) * ny + (iy+nj1-ny2_g);
      iptr_b = iz*ny2_g + iy;
      for(int i=0; i<2*num_of_vars; i++)
      {
        fw_cur[iptr + i*siz_slice_yz] = rbuff_y1_fault[iptr_b+ i*ny2_g*nk];
      }
    }
  }
  return;
}

__global__ void
macdrp_unpack_fault_mesg_y2(
           float *fw_cur, float *rbuff_y2_fault, size_t siz_slice_yz, 
           int num_of_vars, int ny, int nj2, int nk1, int ny1_g, int nk, int *neighid)
{
  int iy = blockIdx.x * blockDim.x + threadIdx.x;
  int iz = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iptr_b;
  size_t iptr;
  if (neighid[3] != MPI_PROC_NULL) {
    if(iy<ny1_g && iz<nk){
      iptr   = (iz+nk1) * ny + (iy+nj2+1);
      iptr_b = iz*ny1_g + iy;
      for(int i=0; i<2*num_of_vars; i++)
      {
        fw_cur[iptr + i*siz_slice_yz] = rbuff_y2_fault[iptr_b+ i*ny1_g*nk];
      }
    }
  }
  return;
}

__global__ void
macdrp_unpack_fault_mesg_z1(
           float *fw_cur, float *rbuff_z1_fault, size_t siz_slice_yz, 
           int num_of_vars, int ny, int nj1, int nk1, int nj, int nz2_g, int *neighid)
{
  int iy = blockIdx.x * blockDim.x + threadIdx.x;
  int iz = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iptr_b;
  size_t iptr;
  if (neighid[4] != MPI_PROC_NULL) {
    if(iy<nj && iz<nz2_g){
      iptr   = (iz+nk1-nz2_g) * ny + (iy+nj1);
      iptr_b = iz*nj + iy;
      for(int i=0; i<2*num_of_vars; i++)
      {
        fw_cur[iptr + i*siz_slice_yz] = rbuff_z1_fault[iptr_b+ i*nz2_g*nj];
      }
    }
  }
  return;
}

__global__ void
macdrp_unpack_fault_mesg_z2(
           float *fw_cur, float *rbuff_z2_fault, size_t siz_slice_yz, 
           int num_of_vars, int ny, int nj1, int nk2, int nj, int nz1_g, int *neighid)
{
  int iy = blockIdx.x * blockDim.x + threadIdx.x;
  int iz = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iptr_b;
  size_t iptr;
  if (neighid[5] != MPI_PROC_NULL) {
    if(iy<nj && iz<nz1_g){
      iptr   = (iz+nk2+1) * ny + (iy+nj1);
      iptr_b = iz*nj + iy;
      for(int i=0; i<2*num_of_vars; i++)
      {
        fw_cur[iptr + i*siz_slice_yz] = rbuff_z2_fault[iptr_b+ i*nz1_g*nj];
      }
    }
  }
  return;
}

int
macdrp_fault_output_mesg_init(mympi_t *mympi,
                              fd_t *fd,
                              int nj,
                              int nk,
                              int num_of_out_vars,
                              int number_fault)
{
  // mpi mesg
  mympi->siz_sbuff_out_fault = 0;
  mympi->siz_rbuff_out_fault = 0;
  // fault var exchange
  mympi->siz_sbuff_y1_out_fault = nk * num_of_out_vars * number_fault;
  mympi->siz_sbuff_y2_out_fault = nk * num_of_out_vars * number_fault;

  mympi->siz_sbuff_z1_out_fault = nj *  num_of_out_vars * number_fault;
  mympi->siz_sbuff_z2_out_fault = nj *  num_of_out_vars * number_fault;

  mympi->siz_rbuff_y1_out_fault = nk * num_of_out_vars * number_fault;
  mympi->siz_rbuff_y2_out_fault = nk * num_of_out_vars * number_fault;

  mympi->siz_rbuff_z1_out_fault = nj * num_of_out_vars * number_fault;
  mympi->siz_rbuff_z2_out_fault = nj * num_of_out_vars * number_fault;

  size_t siz_s = mympi->siz_sbuff_y1_out_fault
               + mympi->siz_sbuff_y2_out_fault
               + mympi->siz_sbuff_z1_out_fault
               + mympi->siz_sbuff_z2_out_fault;

  size_t siz_r = mympi->siz_rbuff_y1_out_fault
               + mympi->siz_rbuff_y2_out_fault
               + mympi->siz_rbuff_z1_out_fault
               + mympi->siz_rbuff_z2_out_fault;

  if (siz_s > mympi->siz_sbuff_out_fault) mympi->siz_sbuff_out_fault = siz_s;
  if (siz_r > mympi->siz_rbuff_out_fault) mympi->siz_rbuff_out_fault = siz_r;
  // alloc in gpu
  mympi->sbuff_out_fault = (float *) cuda_malloc(mympi->siz_sbuff_out_fault * sizeof(MPI_FLOAT));
  mympi->rbuff_out_fault = (float *) cuda_malloc(mympi->siz_rbuff_out_fault * sizeof(MPI_FLOAT));

  return 0;
}

int
fault_var_exchange(gd_t *gd, fault_t F_d, mympi_t *mympi, int *neighid_d)
{
  int nj1 = gd->nj1;
  int nj2 = gd->nj2;
  int nk1 = gd->nk1;
  int nk2 = gd->nk2;
  int nj = gd->nj;
  int nk = gd->nk;
  int ny = gd->ny;
  size_t siz_slice_yz = gd->siz_slice_yz;

  size_t siz_sbuff_y1_out_fault = mympi->siz_sbuff_y1_out_fault;
  size_t siz_sbuff_y2_out_fault = mympi->siz_sbuff_y2_out_fault;
  size_t siz_sbuff_z1_out_fault = mympi->siz_sbuff_z1_out_fault;
  size_t siz_sbuff_z2_out_fault = mympi->siz_sbuff_z2_out_fault;

  float *sbuff_y1_out_fault = mympi->sbuff_out_fault;
  float *sbuff_y2_out_fault = sbuff_y1_out_fault + siz_sbuff_y1_out_fault;
  float *sbuff_z1_out_fault = sbuff_y2_out_fault + siz_sbuff_y2_out_fault;
  float *sbuff_z2_out_fault = sbuff_z1_out_fault + siz_sbuff_z1_out_fault;

  size_t siz_rbuff_y1_out_fault = mympi->siz_rbuff_y1_out_fault;
  size_t siz_rbuff_y2_out_fault = mympi->siz_rbuff_y2_out_fault;
  size_t siz_rbuff_z1_out_fault = mympi->siz_rbuff_z1_out_fault;
  size_t siz_rbuff_z2_out_fault = mympi->siz_rbuff_z2_out_fault;

  float *rbuff_y1_out_fault = mympi->rbuff_out_fault;
  float *rbuff_y2_out_fault = rbuff_y1_out_fault + siz_rbuff_y1_out_fault;
  float *rbuff_z1_out_fault = rbuff_y2_out_fault + siz_rbuff_y2_out_fault;
  float *rbuff_z2_out_fault = rbuff_z1_out_fault + siz_rbuff_z1_out_fault;

  int number_fault = F_d.number_fault;
  int ncmp = F_d.ncmp - 2;
  int ny1_g = 1;
  int ny2_g = 1;
  int nz1_g = 1;
  int nz2_g = 1;
  MPI_Status status;
  // pack
  {
    dim3 block(ny1_g,8);
    dim3 grid;
    grid.x = (ny1_g + block.x -1) / block.x;
    grid.y = (nk + block.y - 1) / block.y;
    int size_y1 = siz_sbuff_y1_out_fault/number_fault; // int/int 
    for(int id=0; id<number_fault; id++)
    {
      // get one fault size
      float *sbuff_y1_thisone = sbuff_y1_out_fault + id*size_y1;
      pack_fault_out_mesg_y1<<<grid, block >>>(
                                   id, F_d, sbuff_y1_thisone, siz_slice_yz, 
                                   ncmp, ny, nj1, nk1, ny1_g, nk);
    }
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(ny2_g,8);
    dim3 grid;
    grid.x = (ny2_g + block.x -1) / block.x;
    grid.y = (nk + block.y - 1) / block.y;
    int size_y2 = siz_sbuff_y2_out_fault/number_fault; // int/int 
    for(int id=0; id<number_fault; id++)
    {
      // get one fault size
      float *sbuff_y2_thisone = sbuff_y2_out_fault + id*size_y2;
      pack_fault_out_mesg_y2<<<grid, block >>>(
                                   id, F_d, sbuff_y2_thisone, siz_slice_yz, 
                                   ncmp, ny, nj2, nk1, ny2_g, nk);
    }
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(8,nz1_g);
    dim3 grid;
    grid.x = (nj + block.x -1) / block.x;
    grid.y = (nz1_g + block.y - 1) / block.y;
    int size_z1 = siz_sbuff_z1_out_fault/number_fault; // int/int 
    for(int id=0; id<number_fault; id++)
    {
      // get one fault size
      float *sbuff_z1_thisone = sbuff_z1_out_fault + id*size_z1;
      pack_fault_out_mesg_z1<<<grid, block >>>(
                                   id, F_d, sbuff_z1_thisone, siz_slice_yz, 
                                   ncmp, ny, nj1, nk1, nj, nz1_g);
    }
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(8,nz2_g);
    dim3 grid;
    grid.x = (nj + block.x -1) / block.x;
    grid.y = (nz2_g + block.y - 1) / block.y;
    int size_z2 = siz_sbuff_z2_out_fault/number_fault; // int/int 
    for(int id=0; id<number_fault; id++)
    {
      // get one fault size
      float *sbuff_z2_thisone = sbuff_z2_out_fault + id*size_z2;
      pack_fault_out_mesg_z2<<<grid, block >>>(
                                   id, F_d, sbuff_z2_thisone, siz_slice_yz, 
                                   ncmp, ny, nj1, nk2, nj, nz2_g);
    }
    CUDACHECK(cudaDeviceSynchronize());
  }
  // send and recv fault var data
  MPI_Sendrecv(sbuff_y1_out_fault, siz_sbuff_y1_out_fault, MPI_FLOAT, mympi->neighid[2], 11,
               rbuff_y2_out_fault, siz_rbuff_y2_out_fault, MPI_FLOAT, mympi->neighid[3], 11,
               mympi->topocomm, &status);
  MPI_Sendrecv(sbuff_y2_out_fault, siz_sbuff_y2_out_fault, MPI_FLOAT, mympi->neighid[3], 22,
               rbuff_y1_out_fault, siz_rbuff_y1_out_fault, MPI_FLOAT, mympi->neighid[2], 22,
               mympi->topocomm, &status);
  MPI_Sendrecv(sbuff_z1_out_fault, siz_sbuff_z1_out_fault, MPI_FLOAT, mympi->neighid[4], 33,
               rbuff_z2_out_fault, siz_rbuff_z2_out_fault, MPI_FLOAT, mympi->neighid[5], 33,
               mympi->topocomm, &status);
  MPI_Sendrecv(sbuff_z2_out_fault, siz_sbuff_z2_out_fault, MPI_FLOAT, mympi->neighid[5], 44,
               rbuff_z1_out_fault, siz_rbuff_z1_out_fault, MPI_FLOAT, mympi->neighid[4], 44,
               mympi->topocomm, &status);

  // unpack
  {
    dim3 block(ny2_g,8);
    dim3 grid;
    grid.x = (ny2_g + block.x -1) / block.x;
    grid.y = (nk + block.y - 1) / block.y;
    int size_y1 = siz_rbuff_y1_out_fault/number_fault; // int/int 
    for(int id=0; id<number_fault; id++)
    {
      // get one fault size
      float *rbuff_y1_thisone = rbuff_y1_out_fault + id*size_y1;
      unpack_fault_out_mesg_y1<<<grid, block >>>(
                                   id, F_d, rbuff_y1_thisone, siz_slice_yz, 
                                   ncmp, ny, nj1, nk1, ny2_g, nk, neighid_d);
    }
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(ny1_g,8);
    dim3 grid;
    grid.x = (ny1_g + block.x -1) / block.x;
    grid.y = (nk + block.y - 1) / block.y;
    int size_y2 = siz_rbuff_y2_out_fault/number_fault; // int/int 
    for(int id=0; id<number_fault; id++)
    {
      // get one fault size
      float *rbuff_y2_thisone = rbuff_y2_out_fault + id*size_y2;
      unpack_fault_out_mesg_y2<<<grid, block >>>(
                                   id, F_d, rbuff_y2_thisone, siz_slice_yz, 
                                   ncmp, ny, nj2, nk1, ny1_g, nk, neighid_d);
    }
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(8,nz2_g);
    dim3 grid;
    grid.x = (nj + block.x -1) / block.x;
    grid.y = (nz2_g + block.y - 1) / block.y;
    int size_z1 = siz_rbuff_z1_out_fault/number_fault; // int/int 
    for(int id=0; id<number_fault; id++)
    {
      // get one fault size
      float *rbuff_z1_thisone = rbuff_z1_out_fault + id*size_z1;
      unpack_fault_out_mesg_z1<<<grid, block >>>(
                                   id, F_d, rbuff_z1_thisone, siz_slice_yz, 
                                   ncmp, ny, nj1, nk1, nj, nz2_g, neighid_d);
    }
    CUDACHECK(cudaDeviceSynchronize());
  }
  {
    dim3 block(8,nz1_g);
    dim3 grid;
    grid.x = (nj + block.x -1) / block.x;
    grid.y = (nz1_g + block.y - 1) / block.y;
    int size_z2 = siz_rbuff_z2_out_fault/number_fault; // int/int 
    for(int id=0; id<number_fault; id++)
    {
      // get one fault size
      float *rbuff_z2_thisone = rbuff_z2_out_fault + id*size_z2;
      unpack_fault_out_mesg_z2<<<grid, block >>>(
                                   id, F_d, rbuff_z2_thisone, siz_slice_yz, 
                                   ncmp, ny, nj1, nk2, nj, nz1_g, neighid_d);
    }
    CUDACHECK(cudaDeviceSynchronize());
  }

  return 0;
}

__global__ void
pack_fault_out_mesg_y1(
             int id, fault_t  F, float *sbuff_y1_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj1, int nk1, int ny1_g, int nk)
{
  int iy = blockIdx.x * blockDim.x + threadIdx.x;
  int iz = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iptr_b;
  size_t iptr;
  fault_one_t *F_thisone = F.fault_one + id;
  if(iy<ny1_g && iz<nk)
  {
    iptr     = (iz+nk1) * ny + (iy+nj1);
    iptr_b   = iz*ny1_g + iy;
    for(int i=0; i<ncmp; i++)
    {
      sbuff_y1_fault[iptr_b + i*ny1_g*nk] = F_thisone->output[iptr + i*siz_slice_yz];
    }
  }

  return;
}

__global__ void
pack_fault_out_mesg_y2(
             int id, fault_t  F, float *sbuff_y2_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj2, int nk1, int ny2_g, int nk)
{
  int iy = blockIdx.x * blockDim.x + threadIdx.x;
  int iz = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iptr_b;
  size_t iptr;
  fault_one_t *F_thisone = F.fault_one + id;
  if(iy<ny2_g && iz<nk)
  {
    iptr     = (iz+nk1) * ny + (iy+nj2-ny2_g+1);
    iptr_b   = iz*ny2_g + iy;
    for(int i=0; i<ncmp; i++)
    {
      sbuff_y2_fault[iptr_b + i*ny2_g*nk] = F_thisone->output[iptr + i*siz_slice_yz];
    }
  }

  return;
}

__global__ void
pack_fault_out_mesg_z1(
             int id, fault_t  F, float *sbuff_z1_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj1, int nk1, int nj, int nz1_g)
{
  int iy = blockIdx.x * blockDim.x + threadIdx.x;
  int iz = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iptr_b;
  size_t iptr;
  fault_one_t *F_thisone = F.fault_one + id;
  if(iy<nj && iz<nz1_g)
  {
    iptr     = (iz+nk1) * ny + (iy+nj1);
    iptr_b   = iz*nj + iy;
    for(int i=0; i<ncmp; i++)
    {
      sbuff_z1_fault[iptr_b + i*nz1_g*nj] = F_thisone->output[iptr + i*siz_slice_yz];
    }
  }

  return;
}

__global__ void
pack_fault_out_mesg_z2(
             int id, fault_t  F, float *sbuff_z2_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj1, int nk2, int nj, int nz2_g)
{
  int iy = blockIdx.x * blockDim.x + threadIdx.x;
  int iz = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iptr_b;
  size_t iptr;
  fault_one_t *F_thisone = F.fault_one + id;
  if(iy<nj && iz<nz2_g)
  {
    iptr     = (iz+nk2-nz2_g+1) * ny + (iy+nj1);
    iptr_b   = iz*nj + iy;
    for(int i=0; i<ncmp; i++)
    {
      sbuff_z2_fault[iptr_b + i*nz2_g*nj] = F_thisone->output[iptr + i*siz_slice_yz];
    }
  }

  return;
}

__global__ void
unpack_fault_out_mesg_y1(
             int id, fault_t F, float *rbuff_y1_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj1, int nk1, int ny2_g, int nk, int *neighid)
{
  int iy = blockIdx.x * blockDim.x + threadIdx.x;
  int iz = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iptr_b;
  size_t iptr;
  fault_one_t *F_thisone = F.fault_one + id;
  if(neighid[2] != MPI_PROC_NULL)
  {
    if(iy<ny2_g && iz<nk)
    {
      iptr     = (iz+nk1) * ny + (iy+nj1-ny2_g);
      iptr_b   = iz*ny2_g + iy;
      for(int i=0; i<ncmp; i++)
      {
        F_thisone->output[iptr + i*siz_slice_yz] = rbuff_y1_fault[iptr_b + i*ny2_g*nk];
      }
    }
  }

  return;
}

__global__ void
unpack_fault_out_mesg_y2(
             int id, fault_t F, float *rbuff_y2_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj2, int nk1, int ny1_g, int nk, int *neighid)
{
  int iy = blockIdx.x * blockDim.x + threadIdx.x;
  int iz = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iptr_b;
  size_t iptr;
  fault_one_t *F_thisone = F.fault_one + id;
  if(neighid[3] != MPI_PROC_NULL)
  {
    if(iy<ny1_g && iz<nk)
    {
      iptr     = (iz+nk1) * ny + (iy+nj2+1);
      iptr_b   = iz*ny1_g + iy;
      for(int i=0; i<ncmp; i++)
      {
        F_thisone->output[iptr + i*siz_slice_yz] = rbuff_y2_fault[iptr_b + i*ny1_g*nk];
      }
    }
  }

  return;
}

__global__ void
unpack_fault_out_mesg_z1(
             int id, fault_t F, float *rbuff_z1_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj1, int nk1, int nj, int nz2_g, int *neighid)
{
  int iy = blockIdx.x * blockDim.x + threadIdx.x;
  int iz = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iptr_b;
  size_t iptr;
  fault_one_t *F_thisone = F.fault_one + id;
  if(neighid[4] != MPI_PROC_NULL)
  {
    if(iy<nj && iz<nz2_g)
    {
      iptr     = (iz+nk1-nz2_g) * ny + (iy+nj1);
      iptr_b   = iz*nj + iy;
      for(int i=0; i<ncmp; i++)
      {
        F_thisone->output[iptr + i*siz_slice_yz] = rbuff_z1_fault[iptr_b + i*nz2_g*nj];
      }
    }
  }

  return;
}

__global__ void
unpack_fault_out_mesg_z2(
             int id, fault_t F, float *rbuff_z2_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj1, int nk2, int nj, int nz1_g, int *neighid)
{
  int iy = blockIdx.x * blockDim.x + threadIdx.x;
  int iz = blockIdx.y * blockDim.y + threadIdx.y;
  size_t iptr_b;
  size_t iptr;
  fault_one_t *F_thisone = F.fault_one + id;
  if(neighid[5] != MPI_PROC_NULL)
  {
    if(iy<nj && iz<nz1_g)
    {
      iptr     = (iz+nk2+1) * ny + (iy+nj1);
      iptr_b   = iz*nj + iy;
      for(int i=0; i<ncmp; i++)
      {
        F_thisone->output[iptr + i*siz_slice_yz] = rbuff_z2_fault[iptr_b + i*nz1_g*nj];
      }
    }
  }

  return;
}

