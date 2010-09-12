%% Clean up.
close all;
clear all;
clc;
%% Comparisons
%  Run the comparisons first, because LaPrint requires
%  the figure number. Seriously, wtf?
if exist('laprint','file')
  run comparison01;
  close all;
  run comparison02;
  close all;
else
  warning('run_all:noLaPrint','LaPrint not found. Skipping the comparisons');
end
%% Run the scripts
ii=1;
while exist( sprintf('ex%02i',ii), 'file' )
  run( sprintf('ex%02i',ii) );
  ii = ii+1;
end
%% Run the extra testing scripts
ii=1;
while exist( sprintf('test%02i',ii), 'file' )
  run( sprintf('test%02i',ii) );
  ii = ii+1;
end