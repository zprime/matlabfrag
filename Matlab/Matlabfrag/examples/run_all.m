%% Clean up.
close all;
clear all;
clc;
%% Run the scripts
numExamples = 11;
for ii=1:numExamples
  run( sprintf('ex%02i',ii) );
end