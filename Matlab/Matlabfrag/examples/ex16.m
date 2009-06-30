%% Preamble -- not to appear in userguide
hfig = figure;
set(hfig,'units','centimeters','NumberTitle','off','Name','ex16');
pos = get(hfig,'position');
set(hfig,'position',[pos(1:2),8,6]);
%% Everything below appears in userguide
peaks;
hs = get(gca,'children');
set(hs,'facealpha',0.5);
hl=legend('legend');
set(hl,'location','northeast');
matlabfrag('graphics/ex16','renderer','opengl','dpi',720);
%% The following is excluded from userguide