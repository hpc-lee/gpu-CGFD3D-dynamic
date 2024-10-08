% fault init stress 
clear;
close all;
clear all;

addmypath;
% if use this script, some parameters is determined by 
% this script, not json.
ny = 960;
nz = 300;
dh = 90; %grid physics length
j1 = 101;
j2 = 896;
k1 = 78;
k2 = 300;


mu_s = 0.340; 
mu_d = 0.275; 
Dc = 0.4;

% nucleation shape. 1 is square, 2 is circle.
nucleation_shape = 2; % circle
nucleation_size = 1500.0; % radius
R2 = nucleation_size + dh * 15; % Transition zone
srcj = 200;
srck = 200;   

% nucleation_shape = 1; % square
% Asp_grid(1,:) = [100 710];
% Asp_grid(2,:) = [210 270];

% 1st method
% R = 0.6;
% SH = 120.0; % sigma1 Horizontal max
% Sv = 20.4;  % sigma2 vertical
% Sh = R*Sv + (1-R)*SH; % sigma3 Horizontal min
%2ed method
%yuhouyun lunwen method
Sv = 120;
SH = 1.88*Sv;
Sh = 0.38*Sv;
[SH, Sh, Sv]'
R = (Sv - Sh)/(SH-Sh)

Stress_pri = [ SH, 0.0, 0.0; ...
              0.0, Sv, 0.0; ...
              0.0, 0.0, Sh]*(-1.0e6);

% azimuth of SH_max, degree in the East of North, x -axis
Angle_SH = 87;

% azimuth of x-axis, degree in the East of North
% angle is fault strike, conf_fault_grid.m has calculate
angle = 120;
Angle_x = 90 + angle; 

% Degree in counter-clockwise,
% from princinpal stress coordinate system to the computational coordinate system
%Degree in clockwise is positive,
theta1 = Angle_SH - Angle_x;
theta = theta1*pi/180.0;

Trans_M = [cos(theta), sin(theta), 0.0; ...
         -sin(theta), cos(theta), 0.0; ...
         0.0,         0.0,        1.0];
Stress_tensor = Trans_M * Stress_pri * Trans_M';

% load fault geometry
fnm_grid   = 'fault_coord_1.nc';
fnm_stress = 'init_stress_1.nc';

x  = ncread(fnm_grid, 'x');
y  = ncread(fnm_grid, 'y');
z  = ncread(fnm_grid, 'z');

x1 = x(j1:j2 , k1:k2);
y1 = y(j1:j2 , k1:k2);
z1 = z(j1:j2 , k1:k2);
vec_n1 = ncread(fnm_grid, 'vec_n');
vec_m = ncread(fnm_grid, 'vec_m');
vec_l = ncread(fnm_grid, 'vec_l');

C0 = zeros(ny, nz);
Ts1 = zeros(ny, nz);
Ts2 = zeros(ny, nz);
Tn = zeros(ny, nz);
str_init_x = zeros(ny, nz);
str_init_y = zeros(ny, nz);
str_init_z = zeros(ny, nz);


for k = 1:nz
  for j = 1:ny

      vec_n = squeeze(vec_n1(:,j,k));
      vec_s1 = squeeze(vec_m(:,j,k));
      vec_s2 = squeeze(vec_l(:,j,k));
      temp_init_stress_xyz = Stress_tensor * vec_n;
     depth = -z(j,k);
     if depth < 5.0e3
     temp_init_stress_xyz = temp_init_stress_xyz*max(depth, dh/3.0)/5.e3;
     end

    % add nucleation patch
    if nucleation_shape == 1 % square
      if j>= Asp_grid(1) && j<=Asp_grid(2) &&...
         k>= Asp_grid(3) && k<=Asp_grid(4)
         Asp_Ratio = 1.0;
       else
         Asp_Ratio = 0.0;
       end
    elseif nucleation_shape == 2
      dist=sqrt((j - srcj)^2 +(k - srck)^2 )*dh;
      if dist > R2
        Asp_Ratio = 0.0;
      elseif dist>nucleation_size
        Asp_Ratio = 0.5*(cos((dist-nucleation_size)/(R2-nucleation_size)*atan(1.0)*4.0)+1.0);
      else
        Asp_Ratio = 1.0;
      end
    end

    tn = dot(temp_init_stress_xyz, vec_n);
    ts_vec = temp_init_stress_xyz - tn*vec_n; 
    ts = norm(ts_vec);
    ts_vec = (Asp_Ratio*((-1.001*mu_s*tn+C0(j,k))-ts)+ts)*ts_vec/max(1.0,ts);
    temp_init_stress_xyz = tn*vec_n + ts_vec;

    str_init_x(j,k) = temp_init_stress_xyz(1);
    str_init_y(j,k) = temp_init_stress_xyz(2);
    str_init_z(j,k) = temp_init_stress_xyz(3);

    Ts1(j,k) = dot(temp_init_stress_xyz , vec_s1);
    Ts2(j,k) = dot(temp_init_stress_xyz , vec_s2);
    Tn(j,k) = dot(temp_init_stress_xyz , vec_n);
  end
end

taus = sqrt(Ts1.^2 + Ts2.^2);
% miu0 = -taus./(Tn);
miu0 = -taus./(mu_s*Tn);
% figure(1); 
% surf(x1, y1, z1, Ts1(j1:j2,k1:k2)/1.0e6); axis equal; shading interp; view([60, 30]); 
% title('Ts1 Strike stress');colormap('jet');colorbar;set(gcf,'color','w');set(get(colorbar(),'Title'),'string','MPa');
% figure(2);
% surf(x1, y1, z1, Ts2(j1:j2,k1:k2)/1.0e6); axis equal; shading interp; view([60, 30]);
% title('Ts2 Dip stress');colormap('jet');colorbar;set(gcf,'color','w');set(get(colorbar(),'Title'),'string','MPa');
% figure(3);
% surf(x1, y1, z1, Tn(j1:j2,k1:k2)/1.0e6 ); axis equal; shading interp; view([60, 30]); 
% title('Tn Normal stress' );colormap('jet');colorbar;set(gcf,'color','w');set(get(colorbar(),'Title'),'string','MPa');
figure(4);
surf(x1, y1, z1, miu0(j1:j2,k1:k2)); axis equal; shading interp; view([60, 30]); 
title(['tangshan fault',char(10),'left initial rupture',char(10),'Ts/(u*Tn)']);
colormap('jet');colorbar;set(gcf,'color','w');
%%
mu_s_mat = zeros(ny, nz);
mu_d_mat = zeros(ny, nz);
Dc_mat = zeros(ny,nz);
mu_s_mat(:, :) = 1000.0;
mu_s_mat(j1:j2, k1:k2) = mu_s;
mu_d_mat(:, :) = mu_d;
Dc_mat(:, :) = Dc;

% figure; surf(x, y, z, mu_s_mat ); axis equal; shading interp; view([60, 30]); title('mu_s' );colormap('jet');colorbar
dTx = zeros(ny, nz);
dTy = zeros(ny, nz);
dTz = zeros(ny, nz);
save_to_file = 1;
if save_to_file
  outfile = fnm_stress;
  disp(['To write file: ', outfile, ' ...'])

  ncid = netcdf.create(outfile, 'NC_CLOBBER');
  ydimid = netcdf.defDim(ncid, 'ny', ny);
  zdimid = netcdf.defDim(ncid, 'nz', nz);
  dimid2 = [ydimid, zdimid];
  
  varid1 = netcdf.defVar(ncid, 'x', 'float', dimid2);
  varid2 = netcdf.defVar(ncid, 'y', 'float', dimid2);
  varid3 = netcdf.defVar(ncid, 'z', 'float', dimid2);
  varid4 = netcdf.defVar(ncid, 'Tx', 'float', dimid2);
  varid5 = netcdf.defVar(ncid, 'Ty', 'float', dimid2);
  varid6 = netcdf.defVar(ncid, 'Tz', 'float', dimid2);
  varid7 = netcdf.defVar(ncid,'dTx','float',dimid2);
  varid8 = netcdf.defVar(ncid,'dTy','float',dimid2);
  varid9 = netcdf.defVar(ncid,'dTz','float',dimid2);
  varid10 = netcdf.defVar(ncid, 'mu_s', 'float', dimid2);
  varid11 = netcdf.defVar(ncid, 'mu_d', 'float', dimid2);
  varid12 = netcdf.defVar(ncid, 'Dc', 'float', dimid2);
  varid13 = netcdf.defVar(ncid, 'C0', 'float', dimid2);  
  netcdf.endDef(ncid);
  
  netcdf.putVar(ncid, varid1, x);
  netcdf.putVar(ncid, varid2, y);
  netcdf.putVar(ncid, varid3, z);
  netcdf.putVar(ncid, varid4, str_init_x);
  netcdf.putVar(ncid, varid5, str_init_y);
  netcdf.putVar(ncid, varid6, str_init_z);
  netcdf.putVar(ncid, varid7, dTx);
  netcdf.putVar(ncid, varid8, dTy);
  netcdf.putVar(ncid, varid9, dTz);
  netcdf.putVar(ncid, varid10, mu_s_mat);
  netcdf.putVar(ncid, varid11, mu_d_mat);
  netcdf.putVar(ncid, varid12, Dc_mat);
  netcdf.putVar(ncid, varid13, C0);
 
  netcdf.close(ncid);

end
