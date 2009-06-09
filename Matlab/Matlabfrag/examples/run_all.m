%% Clean up.
close all;
clear all;
clc;
%% Run the comparisons first, because LaPrint requires
%  the figure number. Seriously, wtf?
run comparison01;
close all;
run comparison02;
close all;
%% Run the scripts
numExamples = 14;
for ii=1:numExamples
  run( sprintf('ex%02i',ii) );
end