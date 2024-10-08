#ifndef IO_FUNCS_H
#define IO_FUNCS_H

#include "constants.h"
#include "fault_info.h"
#include "gd_t.h"
#include "md_t.h"
#include "wav_t.h"

/*************************************************
 * structure
 *************************************************/

// for stations output

// single station
typedef struct
{
  float x;
  float y;
  float z;
  float di;
  float dj;
  float dk;
  int   i;
  int   j;
  int   k;
  size_t   indx1d[CONST_2_NDIM];
  float *seismo;
  char  name[CONST_MAX_STRLEN];
} iorecv_one_t;

typedef struct
{
  int                 total_number;
  int                 max_nt;
  int                 ncmp;
  iorecv_one_t *recvone;
} iorecv_t;

// single station
typedef struct
{
  float x;
  float y;
  float z;
  float di;
  float dj;
  float dk;
  int   i;
  int   j;
  int   k;
  int   f_id;  // fault id
  size_t   indx1d[4];
  float *seismo;
  char  name[CONST_MAX_STRLEN];
} io_fault_recv_one_t;

typedef struct
{
  int  total_number;
  int  max_nt;
  int  ncmp;
  int  flag_swap; 
  io_fault_recv_one_t *fault_recvone;
} io_fault_recv_t;

// line output
typedef struct
{
  int     num_of_lines; 
  int     max_nt;
  int     ncmp;

  int    *line_nr; // number of receivers, for name from input file
  int    *line_seq; // line number, for name from input file
  //int    **recv_ir;
  //int    **recv_jr;
  //int    **recv_kr;
  int    **recv_seq; // recv seq in this line
  int    **recv_iptr;
  float  **recv_x; // for sac output
  float  **recv_y; // for sac output
  float  **recv_z; // for sac output
  float  **recv_seismo;
  char   **line_name;
} ioline_t;

// fault output
typedef struct
{
  // for esti size of working space var
  size_t siz_max_wrk;

  int number_fault;
  int *fault_local_index;
  char **fault_fname;
} iofault_t;

// slice output
typedef struct
{
  // for esti size of working space var
  size_t siz_max_wrk;

  int num_of_slice_x;
  int *slice_x_indx;
  char **slice_x_fname;

  int num_of_slice_y;
  int *slice_y_indx;
  char **slice_y_fname;

  int num_of_slice_z;
  int *slice_z_indx;
  char **slice_z_fname;
} ioslice_t;

// snapshot output
typedef struct
{
  // for esti size of working space var
  size_t siz_max_wrk;

  int num_of_snap;

  int *i1;
  int *j1;
  int *k1;
  int *ni;
  int *nj;
  int *nk;
  int *di;
  int *dj;
  int *dk;
  int *it1;
  int *dit;
  int *out_vel;
  int *out_stress;
  int *out_strain;

  int *i1_to_glob;
  int *j1_to_glob;
  int *k1_to_glob;

  char **fname;
} iosnap_t;

// for nc output

typedef struct
{
  int number_fault;
  int num_of_vars;

  int *ncid;
  int *varid;
}
iofault_nc_t;

typedef struct
{
  int num_of_slice_x;
  int num_of_slice_y;
  int num_of_slice_z;
  int num_of_vars;

  int *ncid_slx;
  int *timeid_slx;
  int *varid_slx;

  int *ncid_sly;
  int *timeid_sly;
  int *varid_sly;

  int *ncid_slz;
  int *timeid_slz;
  int *varid_slz;
}
ioslice_nc_t;

typedef struct
{
  int num_of_snap;
  int *ncid;
  int *timeid;
  int *varid_V;  // [num_of_snap*CONST_NDIM];
  int *varid_T;  // [num_of_snap*CONST_NDIM_2];
  int *varid_E;  // [num_of_snap*CONST_NDIM_2];
  int *cur_it ;  // [num_of_snap];
}
iosnap_nc_t;

/*************************************************
 * function prototype
 *************************************************/
int
io_recv_read_locate(gd_t *gd,
                    iorecv_t  *iorecv,
                    int       nt_total,
                    int       num_of_vars,
                    int       num_of_mpiprocs_z,
                    char      *in_filenm,
                    MPI_Comm  comm,
                    int       myid);

int
io_line_locate(gd_t *gd,
               ioline_t *ioline,
               int    num_of_vars,
               int    nt_total,
               int    number_of_receiver_line,
               int   *receiver_line_index_start,
               int   *receiver_line_index_incre,
               int   *receiver_line_count,
               char **receiver_line_name);

int
io_recv_keep(iorecv_t *iorecv, float *w_pre_d,
             float* buff, int it, int ncmp, size_t siz_icmp);

int
io_line_keep(ioline_t *ioline, float *w_pre_d,
             float *buff, int it, int ncmp, size_t siz_icmp);

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
                char *output_dir);

int
io_slice_nc_create(ioslice_t *ioslice, 
                  int num_of_vars, char **w3d_name,
                  int ni, int nj, int nk,
                  int *topoid, ioslice_nc_t *ioslice_nc);

int
io_slice_nc_put(ioslice_t    *ioslice,
                ioslice_nc_t *ioslice_nc,
                gd_t     *gd,
                float *w_pre_d,
                float *buff,
                int   it,
                float time);

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
                    char *output_dir);

int
io_snap_nc_create(iosnap_t *iosnap, iosnap_nc_t *iosnap_nc, int *topoid);

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
               float time);

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
                               int increk);

__global__ void
io_slice_pack_buff_x(int i, int nj, int nk, size_t siz_iy, size_t siz_iz, float *var, float *buff_d);

__global__ void
io_slice_pack_buff_y(int j, int ni, int nk, size_t siz_iy, size_t siz_iz, float *var, float *buff_d);

__global__ void
io_slice_pack_buff_z(int k, int ni, int nj, size_t siz_iy, size_t siz_iz, float *var, float *buff_d);

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
                  float *buff_d);

int
io_slice_nc_close(ioslice_nc_t *ioslice_nc);

int
io_snap_nc_close(iosnap_nc_t *iosnap_nc);


__global__ void
recv_depth_to_axis(float *all_coords_d, int num_recv, gd_t gd_d, 
                   int *flag_indx, int *flag_depth, 
                   MPI_Comm comm, int myid);

__global__ void 
recv_coords_to_glob_indx(float *all_coords_d, int *all_index_d, 
                         float *all_inc_d, int num_recv, gd_t gd_d, 
                         int *flag_indx, MPI_Comm comm, int myid);

//use trilinear interpolation 
__global__ void
io_recv_line_interp_pack_buff(float *var, float *buff_d, int ncmp, size_t siz_icmp, size_t *indx1d_d);

__global__ void
io_recv_line_pack_buff(float *var, float *buff_d, int ncmp,
                  size_t siz_icmp, int iptr);

int
io_recv_output_sac(iorecv_t *iorecv,
                   float dt,
                   int num_of_vars,
                   char **cmp_name,
                   char *output_dir,
                   char *err_message);
int
io_recv_output_sac_el_iso_strain(iorecv_t *iorecv,
                   float * lam3d,
                   float * mu3d,
                   float dt,
                   char *output_dir,
                   char *err_message);

int
io_recv_output_sac_el_vti_strain(iorecv_t *iorecv,
                        float * c11, float * c13,
                        float * c33, float * c55,
                        float * c66,
                        float dt,
                        char *evtnm,
                        char *output_dir,
                        char *err_message);

int
io_recv_output_sac_el_aniso_strain(iorecv_t *iorecv,
                        float * c11d, float * c12d,
                        float * c13d, float * c14d,
                        float * c15d, float * c16d,
                        float * c22d, float * c23d,
                        float * c24d, float * c25d,
                        float * c26d, float * c33d,
                        float * c34d, float * c35d,
                        float * c36d, float * c44d,
                        float * c45d, float * c46d,
                        float * c55d, float * c56d,
                        float * c66d,
                        float dt,
                        char *evtnm,
                        char *output_dir,
                        char *err_message);

int
io_line_output_sac(ioline_t *ioline,
      float dt, char **cmp_name, char *output_dir);

int
ioslice_print(ioslice_t *ioslice);

int
iosnap_print(iosnap_t *iosnap);

int
iorecv_print(iorecv_t *iorecv);

int
PG_slice_output(float *PG,  gd_t *gd, char *output_dir, char *frame_coords, int* topoid);

int
io_get_nextline(FILE *fp, char *str, int length);

int
io_fault_locate(gd_t *gd, 
                iofault_t *iofault,
                int number_fault,
                int *fault_x_index,
                char *output_fname_part,
                char *output_dir);

int
io_fault_nc_create(iofault_t *iofault, 
                   int ni, int nj, int nk,
                   int *topoid, iofault_nc_t *iofault_nc);

int
io_fault_nc_put(iofault_nc_t *iofault_nc,
                gd_t     *gd,
                fault_t  *F,
                fault_t  F_d,
                float *buff,
                int   it,
                float time);

int
io_fault_end_t_nc_put(iofault_nc_t *iofault_nc,
                      gd_t     *gd,
                      fault_t  *F,
                      fault_t  F_d,
                      float *buff);

__global__ void
io_fault_pack_buff(int nj, int nk, int ny,
                   int id, fault_t F, 
                   size_t cmp_pos, float* buff_d);

int
io_fault_nc_close(iofault_nc_t *iofault_nc);

int
io_fault_recv_read_locate(gd_t      *gd,
                          io_fault_recv_t  *io_fault_recv,
                          int       nt_total,
                          int       num_of_vars,
                          int       *fault_indx,
                          char      *in_filenm,
                          MPI_Comm  comm,
                          int       myid);

int
io_fault_recv_keep(io_fault_recv_t *io_fault_recv, fault_t F_d, 
                   float *buff, int it, size_t siz_slice_yz);

__global__ void
io_fault_recv_interp_pack_buff(
                         int id, fault_t F_d, float *buff_d, int ncmp, 
                         size_t siz_slice_yz, size_t *indx1d_d);

int
io_fault_recv_output_sac(io_fault_recv_t *io_fault_recv,
                         float dt,
                         int num_of_vars,
                         char *output_dir,
                         char *err_message);

#endif
