%% Package matlabfrag for upload to the Mathworks File Exchange.
close all;
clear all;
clc;
addpath ./

%% Compile the figures
cd examples
run_all

%% Compile the documentation
if ispc
  texpath = '';
elseif ismac
  texpath = 'export PATH=$PATH:/usr/texbin:/usr/local/bin; ';
else
  texpath = 'export PATH=$PATH:/usr/bin:/usr/local/bin; ';
end

for ii=1:3
  [res,out] = system( sprintf('%spdflatex -interaction=nonstopmode -shell-escape userguide.tex', texpath ));
  if res ~= 0
    error('package:pdflatex','pdfLaTeX compilation failed with error:\n%s',out);
  end
end

%% Remove GPL from userguide
% During submission to the file exchange, Mathworks search all the files
% for the string "GPL", because they require all files to be covered by the
% BSD license.  Therefore, to prevent submission delays, all instances of
% "/Producer (dvips + GPL Ghostscript..." will have the GPL removed.
cd ..
fin = fopen(['examples',filesep,'userguide.pdf'],'r');
fout = fopen('userguide.pdf','w');
while( ~feof( fin ) )
  line = fgets( fin );
  line = regexprep(line,'GPL\sGhostscript','Ghostscript');
  fwrite( fout, line );
end
fin = fclose(fin);
fout = fclose(fout);

%% Zip it up
zip('matlabfrag',{'matlabfrag.m',...
  'epscompress.*',...
  'userguide.pdf',...
  ['examples',filesep,'userguide.tex'],...
  ['examples',filesep,'testing.tex'],...
  ['examples',filesep,'ex*.m'],...
  ['examples',filesep,'comparison*.m'],...
  ['examples',filesep,'test*.m'] });

%% Clean up the output files
close all
cd examples
delete(['graphics',filesep,'*']);
rmdir('graphics');
delete('userguide.aux');
delete('userguide.log');
delete('userguide.out');
delete('userguide.toc');