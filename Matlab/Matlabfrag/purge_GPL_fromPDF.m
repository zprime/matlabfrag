%% Remove GPL entries to stop stupid people at Mathworks rejecting
%% Matlabfrag
try
  fh = fopen('userguide.pdf','r');
  pdffile = fread(fh,inf,'uint8=>char').';
  fh = fclose(fh);
  pdffile = regexprep(pdffile,'GPL\sGhostscript','Ghostscript');
  fh = fopen('userguide.pdf','w');
  fwrite(fh,pdffile);
  fh = fclose(fh);
catch
  if fh
    fh = fclose(fh);
  end
  rethrow(lasterror);
end
clear fh pdffile