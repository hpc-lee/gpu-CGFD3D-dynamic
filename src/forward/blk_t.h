#ifndef BLK_T_H
#define BLK_T_H

#include "constants.h"
#include "fd_t.h"
#include "fault_info.h"
#include "mympi_t.h"
#include "gd_t.h"
#include "md_t.h"
#include "wav_t.h"
#include "fault_wav_t.h"
#include "bdry_t.h"
#include "io_funcs.h"

/*******************************************************************************
 * structure
 ******************************************************************************/

typedef struct
{
  // name for output file name
  char name[CONST_MAX_STRLEN];

  //// flag of medium
  //int medium_type;

  // fd
  fd_t    *fd;     // collocated grid fd

  // mpi
  mympi_t *mympi;
  
  // coordnate: x3d, y3d, z3d
  gd_t *gd;

  // grid metrics: jac, xi_x, etc
  gd_metric_t *gd_metric;

  // media: rho, lambda, mu etc
  md_t *md;

  // wavefield:
  wav_t *wav;
  
  // free surface
  bdryfree_t *bdryfree;
  
  // pml
  bdrypml_t *bdrypml;
  // exp
  bdryexp_t *bdryexp;
  
  // io
  iorecv_t  *iorecv;
  io_fault_recv_t  *io_fault_recv;
  ioline_t  *ioline;
  iosnap_t  *iosnap;
  ioslice_t *ioslice;
  iofault_t *iofault;

  //fault
  fault_coef_t *fault_coef;
  fault_t *fault;
  fault_wav_t *fault_wav;

  // fname and dir
  char output_fname_part[CONST_MAX_STRLEN];
  // wavefield output
  char output_dir[CONST_MAX_STRLEN];
  // seperate grid output to save grid for repeat simulation
  char grid_export_dir[CONST_MAX_STRLEN];
  // seperate medium output to save medium for repeat simulation
  char media_export_dir[CONST_MAX_STRLEN];

  // exchange between blocks
  // point-to-point values
  int num_of_conn_points;
  int *conn_this_indx;
  int *conn_out_blk;
  int *conn_out_indx;
  // interp point
  int num_of_interp_points;
  int *interp_this_indx;
  int *interp_out_blk;
  int *interp_out_indx;
  float *interp_out_dxyz;

  // mem usage
  size_t number_of_float;
  size_t number_of_btye;
} blk_t;

/*******************************************************************************
 * function prototype
 ******************************************************************************/

int
blk_init(blk_t *blk,
         const int myid);

int
blk_set_output(blk_t *blk,
               mympi_t *mympi,
               char *output_dir,
               char *grid_export_dir,
               char *media_export_dir);

int
blk_print(blk_t *blk);

int
blk_dt_esti_curv(gd_t *gd, md_t *md,
    float CFL, float *dtmax, float *dtmaxVp, float *dtmaxL,
    int *dtmaxi, int *dtmaxj, int *dtmaxk);


float
blk_keep_three_digi(float dt);

int
macdrp_mesg_init(mympi_t *mympi,
                 fd_t *fd,
                 int ni,
                 int nj,
                 int nk,
                 int num_of_vars);

int
macdrp_fault_mesg_init(mympi_t *mympi,
                       fd_t *fd,
                       int nj,
                       int nk,
                       int num_of_vars_fault,
                       int number_fault);
int
blk_macdrp_fault_output_mesg_init(mympi_t *mympi,
                                  fd_t *fd,
                                  int nj,
                                  int nk,
                                  int num_of_out_vars,
                                  int number_fault);

int
macdrp_pack_mesg_gpu(float *w_cur,
                     fd_t *fd,
                     gd_t *gd,
                     mympi_t *mpmpi,
                     int ipair_mpi,
                     int istage_mpi,
                     int ncmp,
                     int myid);

__global__ void
macdrp_pack_mesg_y1(
           float* w_cur,float *sbuff_y1, size_t siz_iy, size_t siz_iz, size_t siz_icmp,
           int num_of_vars, int ni1, int nj1, int nk1, int ni, int ny1_g, int nk);

__global__ void
macdrp_pack_mesg_y2(
           float* w_cur,float *sbuff_y2, size_t siz_iy, size_t siz_iz, size_t siz_icmp,
           int num_of_vars, int ni1, int nj2, int nk1, int ni, int ny2_g, int nk);

__global__ void
macdrp_pack_mesg_z1(
           float *w_cur, float *sbuff_z1, size_t siz_iy, size_t siz_iz, size_t siz_icmp,
           int num_of_vars, int ni1, int nj1, int nk1, int ni, int nj, int nz1_g);

__global__ void
macdrp_pack_mesg_z2(
           float *w_cur, float *sbuff_z2, size_t siz_iy, size_t siz_iz, size_t siz_icmp,
           int num_of_vars, int ni1, int nj1, int nk2, int ni, int nj, int nz2_g);

int 
macdrp_unpack_mesg_gpu(float *w_cur, 
                       fd_t *fd,
                       gd_t *gd,
                       mympi_t *mympi, 
                       int ipair_mpi,
                       int istage_mpi,
                       int ncmp,
                       int *neighid);

__global__ void
macdrp_unpack_mesg_y1(
           float *w_cur, float *rbuff_y1, size_t siz_iy, size_t siz_iz, size_t siz_icmp,
           int num_of_vars, int ni1, int nj1, int nk1, int ni, int ny2_g, int nk, int *neighid);

__global__ void
macdrp_unpack_mesg_y2(
           float *w_cur, float *rbuff_y2, size_t siz_iy, size_t siz_iz, size_t siz_icmp,
           int num_of_vars, int ni1, int nj2, int nk1, int ni, int ny1_g, int nk, int *neighid);

__global__ void
macdrp_unpack_mesg_z1(
           float *w_cur, float *rbuff_z1, size_t siz_iy, size_t siz_iz, size_t siz_icmp,
           int num_of_vars, int ni1, int nj1, int nk1, int ni, int nj, int nz2_g, int *neighid);

__global__ void
macdrp_unpack_mesg_z2(
           float *w_cur, float *rbuff_z2, size_t siz_iy, size_t siz_iz, size_t siz_icmp,
           int num_of_vars, int ni1, int nj1, int nk2, int ni, int nj, int nz1_g, int *neighid);

int 
macdrp_pack_fault_mesg_gpu(float * fw_cur,
                           fd_t *fd,
                           gd_t *gd, 
                           fault_wav_t FW_d,
                           mympi_t *mympi, 
                           int ipair_mpi,
                           int istage_mpi,
                           int myid);

__global__ void
macdrp_pack_fault_mesg_y1(
             float *fw_cur, float *sbuff_y1_fault, size_t siz_slice_yz, 
             int num_of_vars_fault, int ny, int nj1, int nk1, int ny1_g, int nk);

__global__ void
macdrp_pack_fault_mesg_y2(
             float *fw_cur, float *sbuff_y2_fault, size_t siz_slice_yz, 
             int num_of_vars_fault, int ny, int nj2, int nk1, int ny2_g, int nk);

__global__ void
macdrp_pack_fault_mesg_z1(
             float *fw_cur, float *sbuff_z1_fault, size_t siz_slice_yz, 
             int num_of_vars_fault, int ny, int nj1, int nk1, int nj, int nz1_g);

__global__ void
macdrp_pack_fault_mesg_z2(
             float *fw_cur, float *sbuff_z2_fault, size_t siz_slice_yz, 
             int num_of_vars_fault, int ny, int nj1, int nk2, int nj, int nz2_g);

int 
macdrp_unpack_fault_mesg_gpu(float *fw_cur, 
                             fd_t *fd,
                             gd_t *gd,
                             fault_wav_t FW_d,
                             mympi_t *mympi, 
                             int ipair_mpi,
                             int istage_mpi,
                             int *neighid);

__global__ void
macdrp_unpack_fault_mesg_y1(
           float *fw_cur, float *rbuff_y1_fault, size_t siz_slice_yz, 
           int num_of_vars, int ny, int nj1, int nk1, int ny2_g, int nk, int *neighid);

__global__ void
macdrp_unpack_fault_mesg_y2(
           float *fw_cur, float *rbuff_y2_fault, size_t siz_slice_yz, 
           int num_of_vars, int ny, int nj2, int nk1, int ny1_g, int nk, int *neighid);

__global__ void
macdrp_unpack_fault_mesg_z1(
           float *fw_cur, float *rbuff_z1_fault, size_t siz_slice_yz, 
           int num_of_vars, int ny, int nj1, int nk1, int nj, int nz2_g, int *neighid);

__global__ void
macdrp_unpack_fault_mesg_z2(
           float *fw_cur, float *rbuff_z2_fault, size_t siz_slice_yz, 
           int num_of_vars, int ny, int nj1, int nk2, int nj, int nz1_g, int *neighid);

int
macdrp_fault_output_mesg_init(mympi_t *mympi,
                              fd_t *fd,
                              int nj,
                              int nk,
                              int num_of_out_vars,
                              int number_fault);

int
fault_var_exchange(gd_t *gd, fault_t F_d, mympi_t *mympi, int *neighid_d);

__global__ void
pack_fault_out_mesg_y1(
             int id, fault_t F_d, float *sbuff_y1_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj1, int nk1, int ny1_g, int nk);

__global__ void
pack_fault_out_mesg_y2(
             int id, fault_t F_d, float *sbuff_y2_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj2, int nk1, int ny2_g, int nk);

__global__ void
pack_fault_out_mesg_z1(
             int id, fault_t F_d, float *sbuff_z1_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj1, int nk1, int nj, int nz1_g);

__global__ void
pack_fault_out_mesg_z2(
             int id, fault_t F_d, float *sbuff_z2_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj1, int nk2, int nj, int nz2_g);

__global__ void
unpack_fault_out_mesg_y1(
             int id, fault_t F_d, float *rbuff_y1_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj1, int nk1, int ny2_g, int nk, int *neighid);

__global__ void
unpack_fault_out_mesg_y2(
             int id, fault_t F_d, float *rbuff_y2_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj2, int nk1, int ny1_g, int nk, int *neighid);

__global__ void
unpack_fault_out_mesg_z1(
             int id, fault_t F_d, float *rbuff_z1_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj1, int nk1, int nj, int nz2_g, int *neighid);

__global__ void
unpack_fault_out_mesg_z2(
             int id, fault_t F_d, float *rbuff_z2_fault, size_t siz_slice_yz, 
             int ncmp, int ny, int nj1, int nk2, int nj, int nz1_g, int *neighid);

#endif
