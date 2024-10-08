/*
 *
 */

#include <string.h>
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

#include "netcdf.h"

#include "constants.h"
#include "fdlib_mem.h"
#include "md_t.h"

int
md_init(gd_t *gd, md_t *md, int media_type, int visco_type)
{
  int ierr = 0;

  md->nx   = gd->nx;
  md->ny   = gd->ny;
  md->nz   = gd->nz;

  md->siz_iy   = md->nx;
  md->siz_iz  = md->nx * md->ny;
  md->siz_icmp = md->nx * md->ny * md->nz;

  // media type
  md->medium_type = media_type;
  if (media_type == CONST_MEDIUM_ACOUSTIC_ISO) {
    md->ncmp = 2;
  } else if (media_type == CONST_MEDIUM_ELASTIC_ISO) {
    md->ncmp = 3;
  } else if (media_type == CONST_MEDIUM_ELASTIC_VTI) {
    md->ncmp = 6; // 5 + rho
  } else {
    md->ncmp = 22; // 21 + rho
  }

  // visco
  md->visco_type = visco_type;
  if (visco_type == CONST_VISCO_GRAVES_QS) {
   md->ncmp += 1;
  }

  /*
   * 0: rho
   * 1: lambda
   * 2: mu
   */
  
  // vars
  md->v4d = (float *) fdlib_mem_calloc_1d_float(
                          md->siz_icmp * md->ncmp,
                          0.0, "md_init");
  if (md->v4d == NULL) {
      fprintf(stderr,"Error: failed to alloc medium_el_iso\n");
      fflush(stderr);
  }

  // position of each var
  size_t *cmp_pos = (size_t *) fdlib_mem_calloc_1d_sizet(md->ncmp,
                                                         0,
                                                         "medium_el_iso_init");

  // name of each var
  char **cmp_name = (char **) fdlib_mem_malloc_2l_char(md->ncmp,
                                                       CONST_MAX_STRLEN,
                                                       "medium_el_iso_init");

  // set pos
  for (int icmp=0; icmp < md->ncmp; icmp++)
  {
    cmp_pos[icmp] = icmp * md->siz_icmp;
  }

  // init
  int icmp = 0;
  sprintf(cmp_name[icmp],"%s","rho");
  md->rho = md->v4d + cmp_pos[icmp];

  // acoustic iso
  if (media_type == CONST_MEDIUM_ACOUSTIC_ISO) {
    icmp += 1;
    sprintf(cmp_name[icmp],"%s","kappa");
    md->kappa = md->v4d + cmp_pos[icmp];
  }

  // iso
  if (media_type == CONST_MEDIUM_ELASTIC_ISO) {
    icmp += 1;
    sprintf(cmp_name[icmp],"%s","lambda");
    md->lambda = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","mu");
    md->mu = md->v4d + cmp_pos[icmp];
  }

  // vti
  if (media_type == CONST_MEDIUM_ELASTIC_VTI) {
    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c11");
    md->c11 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c13");
    md->c13 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c33");
    md->c33 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c55");
    md->c55 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c66");
    md->c66 = md->v4d + cmp_pos[icmp];
  }

  // aniso
  if (media_type == CONST_MEDIUM_ELASTIC_ANISO) {
    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c11");
    md->c11 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c12");
    md->c12 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c13");
    md->c13 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c14");
    md->c14 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c15");
    md->c15 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c16");
    md->c16 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c22");
    md->c22 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c23");
    md->c23 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c24");
    md->c24 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c25");
    md->c25 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c26");
    md->c26 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c33");
    md->c33 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c34");
    md->c34 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c35");
    md->c35 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c36");
    md->c36 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c44");
    md->c44 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c45");
    md->c45 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c46");
    md->c46 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c55");
    md->c55 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c56");
    md->c56 = md->v4d + cmp_pos[icmp];

    icmp += 1;
    sprintf(cmp_name[icmp],"%s","c66");
    md->c66 = md->v4d + cmp_pos[icmp];
  }

  // plus Qs
  if (visco_type == CONST_VISCO_GRAVES_QS) {
    icmp += 1;
    sprintf(cmp_name[icmp],"%s","Qs");
    md->Qs = md->v4d + cmp_pos[icmp];
  }
  
  // set pointer
  md->cmp_pos  = cmp_pos;
  md->cmp_name = cmp_name;

  return ierr;
}

//
//
//

int
md_import(gd_t *gd, md_t *md, char *fname_coords, char *in_dir)
{
  int ierr = 0;
  // construct file name
  char in_file[CONST_MAX_STRLEN];
  sprintf(in_file, "%s/media_%s.nc", in_dir, fname_coords);

  int ni1 = gd->ni1;
  int nj1 = gd->nj1;
  int nk1 = gd->nk1;
  int ni2 = gd->ni2;
  int nj2 = gd->nj2;
  int nk2 = gd->nk2;
  int ni  = gd->ni;
  int nj  = gd->nj;
  int nk  = gd->nk;
  size_t  siz_iy = gd->siz_iy;
  size_t  siz_iz = gd->siz_iz;
  
  size_t iptr, iptr1;
  
  float *var_in = (float *) malloc(sizeof(float)*ni*nj*nk);
  size_t start[] = {0, 0, 0};
  size_t count[] = {nk, nj, ni};
  
  // read in nc
  int ncid;
  int varid;
  
  ierr = nc_open(in_file, NC_NOWRITE, &ncid); handle_nc_err(ierr);
  
  for (int ivar=0; ivar < md->ncmp; ivar++) 
  {
    ierr = nc_inq_varid(ncid, md->cmp_name[ivar], &varid); handle_nc_err(ierr);
  
    ierr = nc_get_var(ncid,varid,var_in); handle_nc_err(ierr);
    float *ptr = md->v4d + md->cmp_pos[ivar];
    for(int k=nk1; k<=nk2; k++) {
      for(int j=nj1; j<=nj2; j++) {
        for(int i=ni1; i<=ni2; i++)
        {
          iptr = i + j*siz_iy + k*siz_iz; 
          iptr1 = (i-3) + (j-3)*ni + (k-3)*ni*nj; 
          ptr[iptr] = var_in[iptr1];
        }
      }
    }
  }
  mirror_symmetry(gd, md->v4d, md->ncmp);
  
  // close file
  ierr = nc_close(ncid); handle_nc_err(ierr);

  free(var_in);

  return 0;
}

int
md_export(gd_t *gd,
          md_t *md,
          char *fname_coords,
          char *output_dir)
{
  int ierr = 0;

  int  number_of_vars = md->ncmp;
  int  nx = gd->nx;
  int  ny = gd->ny;
  int  nz = gd->nz;
  int  ni1 = gd->ni1;
  int  nj1 = gd->nj1;
  int  nk1 = gd->nk1;
  int  ni2 = gd->ni2;
  int  nj2 = gd->nj2;
  int  nk2 = gd->nk2;
  int  ni  = gd->ni;
  int  nj  = gd->nj;
  int  nk  = gd->nk;
  int  gni1 = gd->gni1;
  int  gnj1 = gd->gnj1;
  int  gnk1 = gd->gnk1;
  size_t  siz_iy = gd->siz_iy;
  size_t  siz_iz = gd->siz_iz;
  size_t iptr, iptr1;

  float *var_out = (float *) malloc(sizeof(float)*ni*nj*nk);

  // construct file name
  char ou_file[CONST_MAX_STRLEN];
  sprintf(ou_file, "%s/media_%s.nc", output_dir, fname_coords);
  
  // read in nc
  int ncid;
  int varid[number_of_vars];
  int dimid[CONST_NDIM];

  ierr = nc_create(ou_file, NC_CLOBBER | NC_64BIT_OFFSET, &ncid); handle_nc_err(ierr);

  // define dimension
  ierr = nc_def_dim(ncid, "i", ni, &dimid[2]);
  ierr = nc_def_dim(ncid, "j", nj, &dimid[1]);
  ierr = nc_def_dim(ncid, "k", nk, &dimid[0]);

  // define vars
  for (int ivar=0; ivar<number_of_vars; ivar++) {
    ierr = nc_def_var(ncid, md->cmp_name[ivar], NC_FLOAT, CONST_NDIM, dimid, &varid[ivar]);
  }

  // attribute:
  int g_start[] = { gni1, gnj1, gnk1 };
  nc_put_att_int(ncid,NC_GLOBAL,"global_index_of_first_physical_points",
                   NC_INT,CONST_NDIM,g_start);

  int l_count[] = { ni, nj, nk };
  nc_put_att_int(ncid,NC_GLOBAL,"count_of_physical_points",
                   NC_INT,CONST_NDIM,l_count);

  // end def
  ierr = nc_enddef(ncid);

  // add vars
  for (int ivar=0; ivar<number_of_vars; ivar++)
  {
    float *ptr = md->v4d + md->cmp_pos[ivar];
    for(int k=nk1; k<=nk2; k++) {
      for(int j=nj1; j<=nj2; j++) {
        for(int i=ni1; i<=ni2; i++)
        {
          iptr = i + j*siz_iy + k*siz_iz; 
          iptr1 = (i-3) + (j-3)*ni + (k-3)*ni*nj; 
          var_out[iptr1] = ptr[iptr];
        }
      }
    }
    ierr = nc_put_var_float(ncid, varid[ivar], var_out);  handle_nc_err(ierr);
    handle_nc_err(ierr);
  }
  
  // close file
  ierr = nc_close(ncid); handle_nc_err(ierr);

  free(var_out);

  return 0;
}

int
md_gen_uniform_el_iso(md_t *md)
{
  int ierr = 0;

  int nx = md->nx;
  int ny = md->ny;
  int nz = md->nz;
  size_t siz_iy  = md->siz_iy;
  size_t siz_iz = md->siz_iz;

  float *lam3d = md->lambda;
  float  *mu3d = md->mu;
  float *rho3d = md->rho;

  //float Vp  = 3000;
  //float Vs  = 2000;
  //float rho = 1500;

  float Vp  = 6000;
  float Vs  = 3464;
  float rho = 2670;

  for (size_t k=0; k<nz; k++)
  {
    for (size_t j=0; j<ny; j++)
    {
      for (size_t i=0; i<nx; i++)
      {
        size_t iptr = i + j * siz_iy + k * siz_iz;
        float mu = Vs*Vs*rho;
        float lam = Vp*Vp*rho - 2.0*mu;
        lam3d[iptr] = lam;
         mu3d[iptr] = mu;
        rho3d[iptr] = rho;
      }
    }
  }

  return ierr;
}

int
md_gen_uniform_Qs(md_t *md, float Qs_freq)
{
  int ierr = 0;

  int nx = md->nx;
  int ny = md->ny;
  int nz = md->nz;
  size_t siz_iy  = md->siz_iy;
  size_t siz_iz = md->siz_iz;

  md->visco_Qs_freq = Qs_freq;

  float *Qs = md->Qs;

  for (size_t k=0; k<nz; k++)
  {
    for (size_t j=0; j<ny; j++)
    {
      for (size_t i=0; i<nx; i++)
      {
        size_t iptr = i + j * siz_iy + k * siz_iz;
        Qs[iptr] = 20;
      }
    }
  }

  return ierr;
}

int
md_gen_uniform_el_vti(md_t *md)
{
  int ierr = 0;

  int nx = md->nx;
  int ny = md->ny;
  int nz = md->nz;
  size_t siz_iy  = md->siz_iy;
  size_t siz_iz = md->siz_iz;
  float rho = 1500; 
  float c11 = 25200000000;
  float c13 = 10962000000;
  float c33 = 18000000000;
  float c55 = 5120000000;
  float c66 = 7168000000;
  for (size_t k=0; k<nz; k++)
  {
    for (size_t j=0; j<ny; j++)
    {
      for (size_t i=0; i<nx; i++)
      {
        size_t iptr = i + j * siz_iy + k * siz_iz;

        md->rho[iptr] = rho; 
	      md->c11[iptr] = c11;
	      md->c13[iptr] = c13;
	      md->c33[iptr] = c33;
	      md->c55[iptr] = c55;
        md->c66[iptr] = c66;
        //-- Vp ~ sqrt(c11/rho) = 4098
      }
    }
  }

  return ierr;
}

int
md_gen_uniform_el_aniso(md_t *md)
{
  int ierr = 0;

  int nx = md->nx;
  int ny = md->ny;
  int nz = md->nz;
  size_t siz_iy  = md->siz_iy;
  size_t siz_iz = md->siz_iz;

  float rho = 1500; 
  float c11 = 25200000000;
  float c12 = 0;
  float c13 = 10962000000;
  float c14 = 0;
  float c15 = 0;
  float c16 = 0;
  float c22 = 0;
  float c23 = 0;
  float c24 = 0;
  float c25 = 0;
  float c26 = 0;
  float c33 = 18000000000;
  float c34 = 0;
  float c35 = 0;
  float c36 = 0;
  float c44 = 0;
  float c45 = 0;
  float c46 = 0;
  float c55 = 5120000000;
  float c56 = 0;
  float c66 = 7168000000;

  for (size_t k=0; k<nz; k++)
  {
    for (size_t j=0; j<ny; j++)
    {
      for (size_t i=0; i<nx; i++)
      {
        size_t iptr = i + j * siz_iy + k * siz_iz;

        md->rho[iptr] = rho; 
	      md->c11[iptr] = c11;
	      md->c12[iptr] = c12;
	      md->c13[iptr] = c13;
	      md->c14[iptr] = c14;
	      md->c15[iptr] = c15;
	      md->c16[iptr] = c16;
	      md->c22[iptr] = c22;
	      md->c23[iptr] = c23;
	      md->c24[iptr] = c24;
	      md->c25[iptr] = c25;
	      md->c26[iptr] = c26;
	      md->c33[iptr] = c33;
	      md->c34[iptr] = c34;
	      md->c35[iptr] = c35;
	      md->c36[iptr] = c36;
	      md->c44[iptr] = c44;
	      md->c45[iptr] = c45;
	      md->c46[iptr] = c46;
	      md->c55[iptr] = c55;
	      md->c56[iptr] = c56;
        md->c66[iptr] = c66;
        //-- Vp ~ sqrt(c11/rho) = 4098
        // convert to VTI media
        md->c12[iptr] = md->c11[iptr] - 2.0*md->c66[iptr]; 
	      md->c22[iptr] = md->c11[iptr];
        md->c23[iptr] = md->c13[iptr];
	      md->c44[iptr] = md->c55[iptr]; 
      }
    }
  }

  return ierr;
}

/*
 * convert rho to slowness to reduce number of arithmetic cal
 */

int
md_rho_to_slow(float *rho, size_t siz_icmp)
{
  int ierr = 0;

  for (size_t iptr=0; iptr<siz_icmp; iptr++) {
    if (rho[iptr] > 1e-10) {
      rho[iptr] = 1.0 / rho[iptr];
    } else {
      rho[iptr] = 0.0;
    }
  }

  return ierr;
}

int
md_ac_Vp_to_kappa(float *rho, float *kappa, size_t siz_icmp)
{
  int ierr = 0;

  for (size_t iptr=0; iptr<siz_icmp; iptr++) {
    if (rho[iptr] > 1e-10) {
      float Vp = kappa[iptr];
      kappa[iptr] = Vp * Vp * rho[iptr];
    } else {
      kappa[iptr] = 0.0;
    }
  }

  return ierr;
}
