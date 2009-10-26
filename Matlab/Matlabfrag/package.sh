#!/usr/bin/env bash
cp ../../Libraries/Matlab/matlabfrag.m .
cp examples/userguide.pdf .
sed -e "s/GPL Ghostscript/Ghostscript/g" -ibkup userguide.pdf
rm userguide.pdfbkup
zip -9 matlabfrag.zip \
matlabfrag.m \
userguide.pdf \
examples/userguide.tex \
examples/testing.tex \
examples/run_all.m \
examples/comparison01.m examples/comparison02.m \
examples/ex01.m examples/ex02.m examples/ex03.m examples/ex04.m examples/ex05.m \
examples/ex06.m examples/ex07.m examples/ex08.m examples/ex09.m examples/ex10.m \
examples/ex11.m examples/ex12.m examples/ex13.m examples/ex14.m examples/ex15.m \
examples/ex16.m examples/ex17.m \
examples/test01.m examples/test02.m examples/test03.m \
examples/test04.m examples/test05.m examples/test06.m examples/test07.m \
examples/test08.m examples/test09.m examples/test10.m examples/test11.m \
examples/test12.m
rm matlabfrag.m