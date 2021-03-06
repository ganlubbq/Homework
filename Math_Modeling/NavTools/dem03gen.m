%
%   dem03gen.m
%
%   program to generate a flight profile for insdem03.m
%
%
clear
close

initpos = [0 0 0];   % initial position
initvel = [0 0 0];   % initial velocity
initacc = [0 0 0];   % initial acceleration

phi=0*pi/180;       % initial roll angle is zero
theta=0*pi/180;     % initial pitch angle is zero
psi=0*pi/180;       % initial yaw angle is zero (thus aircraft is pointed north)

initdcm=eulr2dcm([phi theta psi]);   % Compute initial direction cosine matrix
%                                    % for aircraft attitude (nav-to-body frame)

segparam = [2  10 0.1   0 -999 0 -999 0 0.05;    % 1 - Level acceleration for 10 seconds
            4 NaN NaN NaN -999 0   10 1 0.05;    % 2 - pitch up transition
            1  15 NaN NaN -999 0 -999 0 0.5;    % 3 - 15 second climb
            4 NaN NaN NaN -999 0    0 1 0.05;    % 4 - level off
            4 NaN NaN NaN  -15 3 -999 0 0.05;    % 5 - roll into a turn
            3 NaN NaN  90 -999 0 -999 0 0.0025;    % 6 - 90 degree turn
            4 NaN NaN NaN    0 3 -999 0 0.05;    % 7 - roll back to straight and level
            1  10 NaN NaN -999 0 -999 0 0.5];    % 8 - 10 second straight segment to the West

profile = progen(initpos,initvel,initdcm,segparam);
time = profile(:,19);   % run time in seconds

for k = 1:size(profile,1),
    dcmnb=[profile(k,10:12); profile(k,13:15); profile(k,16:18)];
    dcmbn=dcmnb';
    eulv=dcm2eulr(dcmbn);
    roll(k) = eulv(1)*180/pi;
    pitch(k) = eulv(2)*180/pi;
    yaw(k) = eulv(3)*180/pi; 
    if yaw(k) < 0, yaw(k)=yaw(k)+360; end
end

