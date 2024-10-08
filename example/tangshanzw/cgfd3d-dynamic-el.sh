#!/bin/bash

#set -x
set -e

date

#-- system related dir
#MPIDIR=/data3/lihl/software/openmpi-gnu-4.1.2

#-- r740
MPIDIR=/data/openmpi-4.1.2
#MPIDIR=/share/apps/gnu-4.8.5/mpich-3.3
#MPIDIR=$MPI_ROOT

#-- program related dir
#EXEC_WAVE=`pwd`/../../main_curv_col_el_3d
EXEC_WAVE=/data/home/zhangw/BBG_SUSTech/src/gpu-CGFD3D-dynamic/main_curv_col_el_3d
echo "EXEC_WAVE=$EXEC_WAVE"

#-- input dir
INPUTDIR=`pwd`

#-- output and conf
#PROJDIR=`pwd`/../../tangshan
PROJDIR=/data/home/zhangw/BBG_SUSTech/src/gpu-CGFD3D-dynamic/example/tangshanzw/run2
PAR_FILE=${PROJDIR}/params.json
GRID_DIR=${PROJDIR}/output
MEDIA_DIR=${PROJDIR}/output
OUTPUT_DIR=${PROJDIR}/output

#-- create dir
mkdir -p $PROJDIR
mkdir -p $OUTPUT_DIR
mkdir -p $GRID_DIR
mkdir -p $MEDIA_DIR

#----------------------------------------------------------------------
#-- create main conf
#----------------------------------------------------------------------
cat << ieof > $PAR_FILE
{
  "number_of_total_grid_points_x" : 200,
  "number_of_total_grid_points_y" : 1016,
  "number_of_total_grid_points_z" : 323,

  "number_of_mpiprocs_y" : 1,
  "number_of_mpiprocs_z" : 1,

  "dynamic_method" : 2,
  "fault_grid" : [101,916,101,323],

  "size_of_time_step" : 0.006,
  "number_of_time_steps" : 4000,
  "#time_window_length" : 4,
  "check_stability" : 1,
  "io_time_skip" : 2,

  "boundary_x_left" : {
      "cfspml" : {
          "number_of_layers" : 20,
          "alpha_max" : 3.14,
          "beta_max" : 2.0,
          "ref_vel"  : 7000.0
          }
      },
  "boundary_x_right" : {
      "cfspml" : {
          "number_of_layers" : 20,
          "alpha_max" : 3.14,
          "beta_max" : 2.0,
          "ref_vel"  : 7000.0
          }
      },
  "boundary_y_front" : {
      "cfspml" : {
          "number_of_layers" : 20,
          "alpha_max" : 3.14,
          "beta_max" : 2.0,
          "ref_vel"  : 7000.0
          }
      },
  "boundary_y_back" : {
      "cfspml" : {
          "number_of_layers" : 20,
          "alpha_max" : 3.14,
          "beta_max" : 2.0,
          "ref_vel"  : 7000.0
          }
      },
  "boundary_z_bottom" : {
      "cfspml" : {
          "number_of_layers" : 20,
          "alpha_max" : 3.14,
          "beta_max" : 2.0,
          "ref_vel"  : 7000.0
          }
      },
  "boundary_z_top" : {
      "free" : "timg"
      },



  "grid_generation_method" : {
      "fault_plane" : {
        "fault_geometry_file" : "${INPUTDIR}/prep_fault/fault_coord.nc",
        "fault_init_stress_file" : "${INPUTDIR}/prep_fault/init_stress.nc",
        "fault_inteval" : 90.0
      },
      "#grid_with_fault" : {
        "grid_file" : "${INPUTDIR}/prep_fault/fault_coord.nc",
        "fault_init_stress_file" : "${INPUTDIR}/prep_fault/init_stress.nc",
        "fault_i_gobal_index" : 100.0
      }
  },
  "is_export_grid" : 1,
  "grid_export_dir"   : "$GRID_DIR",

  "metric_calculation_method" : {
      "#import" : "$GRID_DIR",
      "calculate" : 1
  },
  "is_export_metric" : 1,

  "medium" : {
      "type" : "elastic_iso",
      "#input_way" : "infile_layer",
      "#input_way" : "binfile",
      "input_way" : "half_space",
      "#binfile" : {
        "size"    : [1101, 1447, 1252],
        "spacing" : [-10, 10, 10],
        "origin"  : [0.0,0.0,0.0],
        "dim1" : "z",
        "dim2" : "x",
        "dim3" : "y",
        "Vp" : "$INPUTDIR/prep_medium/seam_Vp.bin",
        "Vs" : "$INPUTDIR/prep_medium/seam_Vs.bin",
        "rho" : "$INPUTDIR/prep_medium/seam_rho.bin"
      },
      "iso_half_space" : {
        "Vp" : 6000,
        "Vs" : 3464,
        "rho": 2670
      },
      "#vti_half_space" : {
         "rho" : 1500,
         "c11" : 25200000000,
         "c13" : 10962000000,
         "c33" : 18000000000,
         "c55" : 5120000000,
         "c66" : 7168000000
       },
      "#aniso_half_space" : {
        "rho" : 1500,
        "c11" : 25200000000,
        "c12" : 0,
        "c13" : 10962000000,
        "c14" : 0,
        "c15" : 0,
        "c16" : 0,
        "c22" : 0,
        "c23" : 0,
        "c24" : 0,
        "c25" : 0,
        "c26" : 0,
        "c33" : 18000000000,
        "c34" : 0,
        "c35" : 0,
        "c36" : 0,
        "c44" : 0,
        "c45" : 0,
        "c46" : 0,
        "c55" : 5120000000,
        "c56" : 0,
        "c66" : 7168000000
      },
      "#import" : "$MEDIA_DIR",
      "#infile_layer" : "$INPUTDIR/prep_medium/basin_el_iso.md3lay",
      "#infile_grid" : "$INPUTDIR/prep_medium/topolay_el_iso.md3grd",
      "#equivalent_medium_method" : "loc",
      "#equivalent_medium_method" : "har"
  },

  "is_export_media" : 1,
  "media_export_dir"  : "$MEDIA_DIR",

  "#visco_config" : {
      "type" : "graves_Qs",
      "Qs_freq" : 1.0
  },

  "output_dir" : "$OUTPUT_DIR",

  "in_station_file" : "$INPUTDIR/prep_station/station.list",

  "#receiver_line" : [
    {
      "name" : "line_x_1",
      "grid_index_start"    : [  0, 49, 59 ],
      "grid_index_incre"    : [  1,  0,  0 ],
      "grid_index_count"    : 20
    },
    {
      "name" : "line_y_1",
      "grid_index_start"    : [ 19, 49, 59 ],
      "grid_index_incre"    : [  0,  1,  0 ],
      "grid_index_count"    : 20
    } 
  ],

  "#slice" : {
      "x_index" : [ 51 ],
      "y_index" : [ 120 ],
      "z_index" : [ 199 ]
  },

  "#snapshot" : [
    {
      "name" : "volume_vel",
      "grid_index_start" : [ 0, 0, 199 ],
      "grid_index_count" : [ 100,400, 1 ],
      "grid_index_incre" : [  1, 1, 1 ],
      "time_index_start" : 0,
      "time_index_incre" : 1,
      "save_velocity" : 1,
      "save_stress"   : 0,
      "save_strain"   : 0
    }
  ],

  "check_nan_every_nummber_of_steps" : 0,
  "output_all" : 0 
}
ieof

echo "+ created $PAR_FILE"

#-------------------------------------------------------------------------------
#-- Performce simulation
#-------------------------------------------------------------------------------

#-- get np
NUMPROCS_Y=`grep number_of_mpiprocs_y ${PAR_FILE} | sed 's/:/ /g' | sed 's/,/ /g' | awk '{print $2}'`
NUMPROCS_Z=`grep number_of_mpiprocs_z ${PAR_FILE} | sed 's/:/ /g' | sed 's/,/ /g' | awk '{print $2}'`
NUMPROCS=$(( NUMPROCS_Y*NUMPROCS_Z ))
echo $NUMPROCS_Y $NUMPROCS_Z $NUMPROCS

#-- gen run script
cat << ieof > ${PROJDIR}/cgfd_sim.sh
#!/bin/bash

set -e
printf "\nUse $NUMPROCS CPUs on following nodes:\n"

printf "\nStart simualtion ...\n";
time $MPIDIR/bin/mpiexec -np $NUMPROCS $EXEC_WAVE $PAR_FILE 100 
if [ $? -ne 0 ]; then
    printf "\nSimulation fail! stop!\n"
    exit 1
fi

ieof

#-------------------------------------------------------------------------------
#-- start run
#-------------------------------------------------------------------------------

chmod 755 ${PROJDIR}/cgfd_sim.sh
${PROJDIR}/cgfd_sim.sh
if [ $? -ne 0 ]; then
    printf "\nSimulation fail! stop!\n"
    exit 1
fi

date

# vim:ft=conf:ts=4:sw=4:nu:et:ai:
