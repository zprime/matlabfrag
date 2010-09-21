set(0,'defaulttextinterpreter','latex')

hfig(1) = figure;
set(hfig(1),'NumberTitle','off','Name','test17-fig1');
surf(peaks(23));
xlabel('$\alpha^\beta$');
legend('$\theta = 23$');
matlabfrag('graphics/test17-fig1');

hfig(2) = figure;
set(hfig(2),'NumberTitle','off','Name','test17-fig2');
surf(peaks(34));
xlabel('$\alpha^\beta$');
legend('$\theta = 34$');
matlabfrag('graphics/test17-fig2');

set(0,'defaulttextinterpreter','tex');