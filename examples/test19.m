x=1:0.1:100;
y=sin(x);
y2=sin(x)-1;
fig = figure;
yyaxis left
plot(x,y)
title('$F_z$');
text(pi,0,'$\leftarrow \sin{x} \frac{abc}{de_f}$')
xlabel('yabdxd $F_x\cdot\ y\cdot\phi$')
ylabel('$\varphi$')

ylim([-2 2])

yyaxis right
plot(x,y2)
ylabel('$\varphi_2$')
l = legend({'abcyasdfasdfadsfadsfasdfa','$F_x$'});

matlabfrag('graphics/test19');