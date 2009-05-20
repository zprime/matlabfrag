%% This file gives an example of how to use matlabfrag
% Firstly, lets clean up.
close all;
clear all;
clc;

%% Sizing the figure
% matlabfrag is designed to be more WYSIWYG. So to start, you should set
% the size of figure you want. Let's make the figure 10cm wide and 8cm
% high.

hfig = figure;
% Important step here is to set the units to cm
set(hfig,'units','centimeters','color',[1 1 1]);
% Get the current figure position
hPos = get(hfig,'position');
% Update the width and height to 10cm and 8cm respectively, leaving the
% figure at the same origin.
set(hfig,'position',[hPos(1:2) 10 8]);

% I strongly suggest you use a function for these steps,
% so that you don't have to do this manually every time.

%% Create the figure
% Anonymous gaussian function --- not important for this example
gauss = @(a,b,c,x) a*exp(-(x-b).^2/(2*c^2));

% Some `measurement' data --- not important for this example
npoints = 50;
x = linspace(-5,5,npoints);
ydots = gauss(2,0,2,x) + 0.2*rand([1,npoints]);
h1=plot(x,ydots,'kx');hold on;

% matlabfrag respects the fontsize properties of an axis, thus the
% tick-label size.
set(gca,'FontSize',8);

% matlabfrag is set up to respect the fontsize, fontweight and fontangle
% handles for a label.
title('Gaussian Distribution','fontsize',12,'fontweight','bold',...
  'fontangle','italic');

% If you want to enter LaTeX code, you can do it with no interpreter...
xlabel('Normalised Distance from Hell, $x=\frac{\phi}{\pi\omega}$',...
  'interpreter','none','FontSize',10);

% Or, for more of a WYSIWYG, you can use the LaTeX interpreter
ylabel('Heat (kj) - $\frac{\pi}{2}$','interpreter','latex',...
  'FontSize',10,'fontname','fixedwidth');

% Finally, if you have a label that can't be shown on-screen (e.g. you have
% a macro you want to use instread of raw tex), then you override it with
% the UserData property, prefixing it with `matlabfrag:'.
ht=text(-4,2,'$f(x)=2e^{\frac{-x^2}{8}}$','interpreter','latex');
set(ht,'userdata','matlabfrag:\GaussFunc');
% In the resulting tex file, $f(x)=...$ will be replaced by \GaussFunc

%% Export the figure for psfrag.
% This creates two files, one named Silly-Plot.eps and one named
% Silly-Plot.tex. These can be used in latex directly, or in pdflatex using
% the pstool package.
matlabfrag('Silly-Plot');

% If you feel so inclined, you can manually set which figure handle to use
matlabfrag('Silly-Plot2','handle',hfig);

% You can also pad the eps figure with extra space if required. Negative
% values reduce the size of the eps file.
matlabfrag('Silly-Plot3','epspad',[10,10,10,10]);

%% Include in your document
% To include these files in your document, I recommend using the pstool
% package. pstool will transparently take care of any processing requried
% to include this figure in either latex or pdflatex. An example tex file:
%
% \documentclass[12pt]{article}
% \usepackage[crop=pdfcrop]{pstool}
% \begin{document}
% \psfragfig{Silly-Plot}{
%   \def\GaussFunc{$f(x)=2e^{\frac{-x2}{8}}$}
% }
% \end{document}
%
% Note that we had to define the \GaussFunc macro because it was used with
% the userdata tag.
