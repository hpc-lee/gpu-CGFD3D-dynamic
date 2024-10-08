#ifndef FT_INFO_H
#define FT_INFO_H

#include "gd_t.h"
#include "md_t.h"

/*************************************************
 * structure
 *************************************************/

typedef struct
{

  //Fault coefs
  float *D21_1;
  float *D22_1;
  float *D23_1;
  float *D31_1;
  float *D32_1;
  float *D33_1;

  float *D21_2;
  float *D22_2;
  float *D23_2;
  float *D31_2;
  float *D32_2;
  float *D33_2;

  float *matPlus2Min1; //zhangzhengguo method need
  float *matPlus2Min2;
  float *matPlus2Min3;
  float *matPlus2Min4;
  float *matPlus2Min5;
  float *matMin2Plus1;
  float *matMin2Plus2;
  float *matMin2Plus3;
  float *matMin2Plus4;
  float *matMin2Plus5;

  float *matT1toVx_Min; //zhangwenqiang method need
  float *matVytoVx_Min;
  float *matVztoVx_Min;
  float *matT1toVx_Plus;
  float *matVytoVx_Plus;
  float *matVztoVx_Plus;

  //with free surface
  float *matVx2Vz1;
  float *matVy2Vz1;
  float *matVx2Vz2;
  float *matVy2Vz2;

  float *matPlus2Min1f; //zhangzhengguo
  float *matPlus2Min2f;
  float *matPlus2Min3f;
  float *matMin2Plus1f;
  float *matMin2Plus2f;
  float *matMin2Plus3f;

  float *matT1toVxf_Min; //zhangwenqiang
  float *matVytoVxf_Min;
  float *matT1toVxf_Plus;
  float *matVytoVxf_Plus;
  
  // fault split node, + - media 
  float *lam_f;
  float *mu_f;
  float *rho_f;

  float *vec_n; //normal 
  float *vec_s1; //strike
  float *vec_s2; //dip
  float *x_et;
  float *y_et;
  float *z_et;
} fault_coef_one_t;

typedef struct
{

  int number_fault;
  int *fault_index;
  fault_coef_one_t fault_coef_one[5];
} fault_coef_t;

typedef struct
{

  float *T0x;
  float *T0y;
  float *T0z;
  float *mu_s;
  float *mu_d;
  float *Dc;
  float *C0;
  
  float *output;
  float *Tn;
  float *Ts1;
  float *Ts2;
  float *Slip;
  float *Slip1;
  float *Slip2;
  float *Vs;
  float *Vs1;
  float *Vs2;
  float *Peak_vs;
  float *Init_t0;

  float *tTn;
  float *tTs1;
  float *tTs2;
  int *united;
  int *faultgrid;
  int *rup_index_y;
  int *rup_index_z;
  int *flag_rup;
  int *init_t0_flag;
} fault_one_t;

typedef struct
{
  
  size_t *cmp_pos;
  char  **cmp_name;
  int ncmp; //output number
  int number_fault;
  int *fault_index;
  fault_one_t fault_one[5];
} fault_t;


/*************************************************
 * function prototype
 *************************************************/

int
fault_coef_init(fault_coef_t *FC,
                gd_t *gd,
                int number_fault,
                int *fault_x_index);

int 
fault_coef_cal(gd_t *gd, 
               gd_metric_t *metric, 
               md_t *md, 
               fault_coef_t *FC);

int
fault_init(fault_t *F,
           gd_t *gd,
           int number_fault,
           int *fault_x_index);

int
fault_set(fault_t *F,
          fault_coef_t *FC,
          gd_t *gd,
          int bdry_has_free,
          int *fault_grid,
          char *init_stress_dir);

int 
nc_read_init_stress(fault_one_t *F_thisone, 
                    gd_t *gd, 
                    int id,
                    char *init_stress_dir);

#endif
