%  gps11stpv2.m
%
%  Variation of GPS11STPV.M where now
%  we are incorporating delta-range
%  measurements before, at, and after
%  the Kalman update time.
%
%  The state vector is:
%   x1 = delta x position
%   x2 = delta x velocity
%   x3 = delta x acceleration
%   x4 = delta y position
%   x5 = delta y velocity
%   x6 = delta y acceleration
%   x7 = delta z position
%   x8 = delta z velocity
%   x9 = delta z acceleration
%   x10 = clock offset
%   x11 = clock drift
%

%  August 2004;  August 2005
%  Copyright (c) 2004-2005 by GPSoft LLC
%  All Rights Reserved.
%

clear all
close all
randn('state',0)
%
load dogleg20hz     % truth and INS data are generated in 
%                   % an East-North-Up coordinate system
usrenu = tru_pos_L;
%
mpmat=mpgen(24,3600,1,54321);

% Specify the origin of the local-level coordinate frame
lat = 39; lon = -81;
orgllh = [39*pi/180 -81*pi/180 0];
orgxyz = llh2xyz(orgllh);

% Now compute the direction cosine matrix relating ECEF
% xyz coordinates to a local Up-East-North frame
clat = cos(-lat*pi/180); clon = cos(lon*pi/180);
slat = sin(-lat*pi/180); slon = sin(lon*pi/180);
Cz = [clon slon 0; -slon clon 0; 0 0 1];
Cy = [clat 0 -slat; 0 1 0; slat 0 clat];
Cxyz2uen=Cy*Cz;

loadgps
speedoflight = 299792458;

deltat=1;
Sp=10; Sf=1e-3; Sg=1e-3; tauaccel=60;
[Q,PHI] = q_gen_11_gps(deltat,Sp,Sf,Sg,tauaccel);
sigmazpr = 1;
sigmazdr = 0.1;

I = eye(11);
x_pre = zeros(11,1);
P_pre = 100*eye(11); P_pre(3,3)=1; P_pre(6,6)=1; P_pre(9,9)=1;


EndLoop = max(size(usrenu));
bar1 = waitbar(0,'Generating User Solutions...  ');
k = 0;
for i = 1:20:EndLoop-1,
    
    k = k + 1;
    t(k) = tru_time(i);
    usrxyz=enu2xyz(usrenu(i,:),orgxyz);
    [svxyzmat,svid] = gensv(usrxyz,t(k),5);

    %  In the following we are gathering measurements one epoch (20 ms)
    %  prior to the Kalman update and one epoch after the Kalman update.
    %  We will be using these measurements to calculate average velocity
    %  over the entire interval from -20ms to +20 ms around the Kalman
    %  update.
    if i > 1,
        usrxyz_prev=enu2xyz(usrenu(i-1,:),orgxyz);
        [svxyz_prev,svid_prev] = gensv(usrxyz,tru_time(i-1),5);
        [prvec_prev,adrvec_prev] = genrng(1,usrxyz_prev,svxyz_prev,svid_prev,tru_time(i-1),[1 0 0 0 0],[],mpmat);
        adrvec_prev = adrvec_prev + speedoflight*tru_time(i-1)*1e-7;
        usrxyz_futr=enu2xyz(usrenu(i+1,:),orgxyz);
        [svxyz_futr,svid_futr] = gensv(usrxyz,tru_time(i+1),5);
        [prvec_futr,adrvec_futr] = genrng(1,usrxyz_futr,svxyz_futr,svid_futr,tru_time(i+1),[1 0 0 0 0],[],mpmat);
        adrvec_futr = adrvec_futr + speedoflight*tru_time(i+1)*1e-7;
    end
    [prvec,adrvec] = genrng(1,usrxyz,svxyzmat,svid,t(k),[1 0 0 0 0],[],mpmat);
        prvec = prvec + speedoflight*t(k)*1e-7;  % simulate clock offset and drift
        adrvec = adrvec + speedoflight*t(k)*1e-7;
    if i == 1,
        estenuvel = tru_vel_L(1,:);
             estusr = olspos(prvec,svxyzmat);
             x_nom=zeros(11,1); x_nom(1)=estusr(1); x_nom(4)=estusr(2);
                                x_nom(7)=estusr(3); x_nom(10)=estusr(4);
             estuenvel = [estenuvel(3) estenuvel(1) estenuvel(2)];
             estxyzvel = (Cxyz2uen')*estuenvel';
                                x_nom(2)=estxyzvel(1); x_nom(5)=estxyzvel(2);
                                x_nom(8)=estxyzvel(3); x_nom(11)=0;
    else
        n = length(svid);
        deltarange1 = (adrvec - adrvec_prev)/(tru_time(i)-tru_time(i-1));
        deltarange2 = (adrvec_futr - adrvec)/(tru_time(i+1)-tru_time(i));
        estusr = olspos(prvec,svxyzmat);
        clear H z
        H = hmat(svxyzmat,estusr(1:3));   % Note that in the two usages of H below, the
        %                               % signs are reversed with respect
        %                               to the algorithm described in the
        %                               notes.  This is because the
        %                               function HMAT calculates direction
        %                               cosines for a unit vector from the
        %                               satellite to the receiver whereas
        %                               the velocity algorithm is expecting
        %                               the reverse unit vector
        for j = 1:n,
            svjvel = (1/(tru_time(i+1)-tru_time(i-1)))*( svxyz_futr(j,:) - svxyz_prev(j,:) )';
            svrr = -H(j,1:3)*svjvel;
            z(j,1) = mean([deltarange1(j) deltarange2(j)]) - svrr;
        end
        H2partial = H;
        z2 = z;
        estolsusrvel = H\z;
        estolsuenvel=Cxyz2uen*estolsusrvel(1:3);
        estolsenuvel(k,:) = [estolsuenvel(2) estolsuenvel(3) estolsuenvel(1)];
        olsvel_err(k,:) = estolsenuvel(k,:) - tru_vel_L(i,:);
        olstdoterr(k) = estolsusrvel(4) - speedoflight*1e-7;
           
        n = length(svid);
        nom_pos = [x_nom(1) x_nom(4) x_nom(7)];
           
        Hpartial = hmat(svxyzmat,nom_pos);
        H = zeros(n,11); H(:,1)=Hpartial(:,1); H(:,4)=Hpartial(:,2);
        H(:,7)=Hpartial(:,3); H(:,10)=Hpartial(:,4);
           
        H(n+1:2*n,2)=Hpartial(:,1); H(n+1:2*n,5)=Hpartial(:,2);
        H(n+1:2*n,8)=Hpartial(:,3); H(n+1:2*n,11)=Hpartial(:,4);
           
        for j = 1:n,
            pr0 = norm(svxyzmat(j,:) - nom_pos) + x_nom(10);
            z(j,1) = prvec(j) - pr0;
        end
        nom_vel = [x_nom(2) x_nom(5) x_nom(8) x_nom(11)]';
        for j = 1:n,
            svjvel = (1/(tru_time(i+1)-tru_time(i-1)))*( svxyz_futr(j,:) - svxyz_prev(j,:) )';
            svrr = -Hpartial(j,1:3)*svjvel;
            nomrr = Hpartial(j,:)*nom_vel;
            z(j+8,1) = mean([deltarange1(j) deltarange2(j)]) - svrr - nomrr;
        end

        R = eye(2*n);
        R(1:n,1:n) = sigmazpr*R(1:n,1:n);
        R(n+1:2*n,n+1:2*n) = sigmazdr*R(n+1:2*n,n+1:2*n);
           
        K = P_pre*H'*inv(H*P_pre*H' + R);
        x_est = x_pre + K*(z - H*x_pre);
        P = (I - K*H)*P_pre;
           
        x_tot_est = x_nom + x_est;
            estusr = [x_tot_est(1) x_tot_est(4) x_tot_est(7) x_tot_est(10)];
            estusr_rate = [x_tot_est(2) x_tot_est(5) x_tot_est(8) x_tot_est(11)];
            estuenvel=Cxyz2uen*estusr_rate(1:3)';
            estenuvel(k,:) = [estuenvel(2) estuenvel(3) estuenvel(1)];
        x_nom = PHI*x_tot_est;
        x_pre = zeros(11,1);
        P_pre = PHI*P*PHI' + Q;
           
        estenu(k,:) = ( xyz2enu(estusr(1:3),orgxyz) )';
        estclockb(k) = estusr(4);
        err(k,1:3) = estenu(k,1:3) - usrenu(i,:);
        terr(k) = estusr(4) - speedoflight*t(k)*1e-7;
        
    end  % end 'if i == 1' loop
    waitbar(i/EndLoop)   
    
end  % end 'for i = 1:20:EndLoop-1' loop
close(bar1);

figure
subplot(211)
plot(t,estolsenuvel(:,1),tru_time,tru_vel_L(:,1))
ylabel('east velocity [m/s]')
title('GPS Ordinary Least Squares Estimation')
text(30,150,'truth and estimate overlying each other')
subplot(212)
plot(t,estolsenuvel(:,2),tru_time,tru_vel_L(:,2))
ylabel('north velocity [m/s]')
xlabel('run time in seconds')
text(30,130,'truth and estimate overlying each other')

figure
plot(t,olsvel_err(:,1),'-',t,olsvel_err(:,2),':')
ylabel('velocity error in meters/second')
xlabel('run time in seconds')
title('GPS Ordinary Least Squares Velocity Estimation Errors')
legend('x','y',0)
axis([0 150 -1 1])

figure
vel_err = estenuvel - tru_vel_L(1:20:EndLoop,:);
plot(t,vel_err(:,1),t,vel_err(:,2))
ylabel('velocity error in meters/second')
xlabel('run time in seconds')
title('GPS 11-State Kalman Estimation Errors')
legend('x','y',0)
axis([0 150 -1 1])

% figure
% plot(t,olsvel_err(:,3),'-',t,olstdoterr,':')
% ylabel('velocity error in meters/second')
% xlabel('run time in seconds')
% title('GPS Ordinary Least Squares Estimation Errors')
% legend('z','clock-drift',0)
% axis([0 150 -1 1])

figure
plot(usrenu(:,1),usrenu(:,2),'-',estenu(:,1),estenu(:,2),'*')
title('True and Estimated Trajectories')
ylabel('north direction [meters]')
xlabel('east direction [meters]')

% figure
% plot(t,err(:,1),t,err(:,2),t,err(:,3),t,terr)
% ylabel('error in meters')
% xlabel('run time in seconds')
% title('GPS 11-State Kalman Estimation Errors')
% legend('x','y','z','b',0)

figure
plot(t,err(:,1),t,err(:,2),t,err(:,3),t,terr)
ylabel('position error in meters')
xlabel('run time in seconds')
title('GPS 11-State EKF with Pseudorange and Delta-Range')
legend('x','y','z','b',0)
axis([0 150 -7 3])

% figure
% vel_err = estenuvel - tru_vel_L(1:20:EndLoop,:);
% plot(t,vel_err(:,1),t,vel_err(:,2),t,vel_err(:,3))
% ylabel('velocity error in meters/second')
% xlabel('run time in seconds')
% title('GPS 11-State Kalman Estimation Errors')
% legend('x','y','z',0)

figure
vel_err = estenuvel - tru_vel_L(1:20:EndLoop,:);
plot(t,vel_err(:,1),t,vel_err(:,2),t,vel_err(:,3))
ylabel('velocity error in meters/second')
xlabel('run time in seconds')
title('GPS 11-State EKF with Pseudorange and Delta-Range')
legend('x','y','z',0)
axis([0 150 -6 6])
