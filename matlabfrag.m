% function matlabfrag(FileName,OPTIONS)
%  Exports a matlab figure to an .eps file and a .tex file for use with
%  psfrag in LaTeX.  It provides similar functionality to Laprint, but
%  with an emphasis on making it more WYSIWYG, and respecting the handle
%  options for any given text, such as fontsize, fontweight, fontangle,
%  etc.
%
%  .tex file entries can be overridden by placing a string in the
%  'UserData' field of the text handle, prefixed by 'matlabfrag:'.
%
%  For use in pdflatex, I recommend the pstool package.
%
% INPUTS
%  FileName (Required) - A string containting the name of the output files.
%  OPTIONS (Optional) - additional options are added in 'key' and 'value'
%                       pairs
%    Key           |   Value
%    ----------------------------------------------------------------------
%    'handle'      | Figure to create the .eps and .tex files from.
%                  |  default is gcf (current figure handle)
%    'epspad'      | [Left,Bottom,Right,Top] - Pad the eps figure by
%                  |  the number of points in the input vector. Default
%                  |  is [0,0,0,0].
%    'renderer'    | ['painters'|'opengl'|'zbuffer'] - The renderer used
%                  |  to generate the figure. The default is 'painters'.
%                  |  If you have manually specified the renderer,
%                  |  matlabfrag will use this value.
%    'dpi'         | DPI to print the images at. Default is 300 for OpenGL
%                  |  or Z-Buffer images, and 3200 for painters images.
%    'compress'    | [0|1|true|false] - whether to compress the resulting
%                  |   eps file or not. Default is true (compression on).
%    'unaryminus'  | ['normal'|'short'] - whether to use a short or normal
%                  |   unary minus sign on tick labels. Default is 'normal'.
%
% EXAMPLE
% plot(1:10,rand(1,10));
% set(gca,'FontSize',8);
% title('badness $\phi$','interpreter','latex','fontweight','bold');
% xlabel('1 to 10','userdata','matlabfrag:\macro');
% ylabel('random','fontsize',14);
% matlabfrag('RandPlot','epspad',[5,0,0,0],'compress',false);
%
% v0.7.0devb04 30-May-2013
%
% Please report bugs as issues on <a href="matlab:web('http://github.com/zprime/matlabfrag','-browser')">github</a>.
%
% Released on the <a href="matlab:web('http://www.mathworks.com/matlabcentral/fileexchange/21286','-browser')">Matlab File Exchange</a>

function matlabfrag(FileName,varargin)

% Nice output if the user calls matlabfrag without any parameters.
if nargin == 0
  help matlabfrag
  return;
end

% Matlab version check
v = version;
v = regexp(v,'(\d+)\.(\d+)\.\d+\.\d+','tokens');
v = str2double(v{1});
if v(1) < 7
  error('matlabfrag:oldMatlab','Matlabfrag requires Matlab r2007a or newer to run');
elseif v(1) == 7
  if v(2) < 4
    error('matlabfrag:oldMatlab','Matlabfrag requires Matlab r2007a or newer to run');
  end
end

% Version information is taken from the above help information
HelpText = help('matlabfrag');
LatestVersion = regexp(HelpText,'(v[\d\.]+\w*?) ([\d]+\-[\w]+\-[\d]+)','tokens');
LatestVersion = LatestVersion{1};
Version = LatestVersion{1};
VersionDate = LatestVersion{2};
TEXHDR = sprintf('%% Generated using matlabfrag\n%% Version: %s\n%% Version Date: %s\n%% Author: Zebb Prime',...
  Version,VersionDate);

% Global macros
REPLACEMENT_FORMAT = '%03d';
USERDATA_PREFIX = 'matlabfrag:';
NEGTICK_SHORT_COMMAND = 'matlabfragNegTickShort';
NEGTICK_SHORT_SCRIPT_COMMAND = 'matlabfragNegTickShortScript';
NEGTICK_NO_WIDTH_COMMAND = 'matlabfragNegTickNoWidth';
ACTION_FUNC_NAME = @(x) sprintf('f%i',x);
ACTION_DESC_NAME = @(x) sprintf('d%i',x);

% Debug macro levels
KEEP_TEMPFILE = 1;
SHOW_OPTIONS = 1;
PAUSE_BEFORE_PRINT = 2;
PAUSE_AFTER_PRINT = 2;
STEP_THROUGH_ACTIONS = 3;

p = inputParser;
p.FunctionName = 'matlabfrag';

p.addRequired('FileName', @(x) ischar(x) );
p.addParamValue('handle', gcf, @(x) ishandle(x) && strcmpi(get(x,'Type'),'figure') );
p.addParamValue('epspad', [0,0,0,0], @(x) isnumeric(x) && (all(size(x) == [1 4])) );
p.addParamValue('renderer', 'painters', ...
  @(x) any( strcmpi(x,{'painters','opengl','zbuffer'}) ) );
p.addParamValue('dpi', 300, @(x) isnumeric(x) );
p.addParamValue('compress',1, @(x) (isnumeric(x) || islogical(x) ) );
p.addParamValue('debuglvl',0, @(x) isnumeric(x) && x>=0);
p.addParamValue('unaryminus','normal', @(x) any( strcmpi(x,{'short','normal'}) ) );
p.parse(FileName,varargin{:});

if p.Results.debuglvl >= SHOW_OPTIONS
  fprintf(1,'OPTION: FileName = %s\n',p.Results.FileName);
  fprintf(1,'OPTION: handle = %f\n',p.Results.handle);
  fprintf(1,'OPTION: epspad = [%i %i %i %i]\n',p.Results.epspad);
  fprintf(1,'OPTION: renderer = %s\n',p.Results.renderer);
  fprintf(1,'OPTION: dpi = %i\n',p.Results.dpi);
  fprintf(1,'OPTION: debuglvl = %i\n',p.Results.debuglvl);
  fprintf(1,'OPTION: compress = %i\n',p.Results.compress);
  fprintf(1,'OPTION: unaryminus = %s\n',p.Results.unaryminus);
  fprintf(1,'OPTION: Parameters using their defaults:');
  fprintf(1,' %s',p.UsingDefaults{:});
  fprintf(1,'\n');
end

if FigureHasNoText(p)
  return;
end

% Tick unary minus commands. Used to have a zero width X minus (for nice
% alignment), and shorter minus signs if requested.
if strcmpi(p.Results.unaryminus,'short')
  writeOutNegTickNoWidth = @(fid) fprintf(fid,'\n\\providecommand\\%s{\\scalebox{0.6}[1]{\\makebox[0pt][r]{\\ensuremath{-}}}}%%',NEGTICK_NO_WIDTH_COMMAND);
  writeOutNegTickShort = @(fid) fprintf(fid,'\n\\providecommand\\%s{\\scalebox{0.6}[1]{\\ensuremath{-}}}%%',NEGTICK_SHORT_COMMAND);
  writeOutNegTickShortScript = @(fid) fprintf(fid,'\n\\providecommand\\%s{\\scalebox{0.6}[1]{\\ensuremath{\\scriptstyle -}}}%%',NEGTICK_SHORT_SCRIPT_COMMAND);
else
  writeOutNegTickNoWidth = @(fid) fprintf(fid,'\n\\providecommand\\%s{\\makebox[0pt][r]{\\ensuremath{-}}}%%',NEGTICK_NO_WIDTH_COMMAND);
end

% Create Action and UndoAction structures, and initialise the length field
% to 0.
Actions.length = 0;
UndoActions.length = 0;
StringCounter = 0;

% PsfragCmds are currently in the order:
% {LatexString, ReplacementString, Alignment, TextSize, Colour,
%   FontAngle (1-italic,0-normal), FontWeight (1-bold,0-normal),
%   FixedWidth (1-true,0-false), LabelType }
PsfragCmds = {};

% Before doing anthing to the figure, make sure it is fully drawn
drawnow;

% Set up the page size to be printed
Units = get(p.Results.handle,'Units');
set(p.Results.handle,'Units','centimeters');
Pos = get(p.Results.handle,'Position');
set(p.Results.handle,'Units',Units);
SetUnsetProperties('PaperUnits to cm, PaperPos to Pos',p.Results.handle,...
  'PaperUnits','centimeters','PaperPosition',Pos);

% Process the picture
ProcessFigure(p.Results.handle);

% Apply the actions resulting from the processing
if p.Results.debuglvl >= STEP_THROUGH_ACTIONS
  disp('STEPPING: Starting to apply actions');
  for ii=1:Actions.length
    fprintf(1,'STEPPING: Press space to apply: %s\n',Actions.( ACTION_DESC_NAME(ii) ));
    pause;
    Actions.( ACTION_FUNC_NAME(ii) )();
  end
  disp('STEPPING: Finished applying actions');
else
  for ii=1:Actions.length
    Actions.( ACTION_FUNC_NAME(ii) )();
  end
end

if p.Results.debuglvl >= PAUSE_BEFORE_PRINT
  disp('PAUSING: Paused before printing');
  pause;
end

% Test to see if the directory (if specified) exists
[pathstr,namestr] = fileparts(FileName);
if ~isempty(pathstr)
  currentdir = pwd;
  try
    cd(pathstr);
  catch %#ok
    % Create it if it doesn't exist
    mkdir(pathstr);
    cd(pathstr);
  end
  % Tidy up the string
  pathstr = pwd;
  cd(currentdir);
  FileName = [pathstr,filesep,namestr];
else
  FileName = namestr;
end

dpiswitch = ['-r',num2str( round( p.Results.dpi ) )];
% Unless over-ridden, check to see if 'renderermode' is 'manual'
renderer = lower( p.Results.renderer );
if any( strcmpi(p.UsingDefaults,'renderer') )
  if strcmpi(get(p.Results.handle,'renderermode'),'manual')
    renderer = lower( get(p.Results.handle,'renderer') );
    if p.Results.debuglvl >= SHOW_OPTIONS
      fprintf(1,['OPTION: Renderer being overridden by manual renderermode.\n',...
        '        It is now %s.\n'],renderer);
    end
  end
end

if strcmpi(renderer,'painters')
  % If using default dpi
  if any( strcmpi(p.UsingDefaults,'dpi') )
    current_dpi = 3200;
  else
    current_dpi = p.Results.dpi;
  end
    
  % Test to see whether the DPI is too high or not.
  temp_units = get(p.Results.handle,'units');
  set(p.Results.handle,'units','inches');
  temp_pos = get(p.Results.handle,'position');
  set(p.Results.handle,'units',temp_units);
  
  if temp_pos(3) * current_dpi > 32000
    old_dpi = current_dpi;
    current_dpi = 100*floor((30000 / temp_pos(3))/100);
    warning('matlabfrag:ImageTooWide',...
      ['Figure width is too large for %i DPI. Reducing\n',...
      'it to %i DPI.'],old_dpi,current_dpi);
  end
  
  if temp_pos(4) * current_dpi > 32000
    old_dpi = current_dpi;
    current_dpi = 100*floor((30000 / temp_pos(4))/100);
    warning('matlabfrag:defaultDPI:ImageTooHigh',...
      ['Figure height is too large for %i DPI. Reducing\n',...
      'it to %i DPI.'],old_dpi,current_dpi);
  end
  
  dpiswitch = sprintf('-r%i',current_dpi);
  clear temp_units temp_pos current_dpi old_dpi

  % Export the image to an eps file
  drawnow;
  print(p.Results.handle,'-depsc2','-loose',dpiswitch,'-painters',FileName);
  FileWait( [FileName,'.eps'] );
else
  % If using the opengl or zbuffer renderer
  EpsCombine(p.Results.handle,renderer,FileName,dpiswitch,...
    p.Results.debuglvl>=KEEP_TEMPFILE)
end

if p.Results.debuglvl >= PAUSE_AFTER_PRINT
  disp('PAUSING: Paused after printing');
  pause;
end

% Pad the eps if requested
if any( p.Results.epspad )
  fh = fopen([FileName,'.eps'],'r');
  epsfile = fread(fh,inf,'uint8=>char').';
  fclose(fh);
  bb = regexpi(epsfile,'\%\%BoundingBox:\s+(-*\d+)\s+(-*\d+)\s+(-*\d+)\s+(-*\d+)','tokens');
  bb = str2double(bb{1});
  epsfile = regexprep(epsfile,sprintf('%i(\\s+)%i(\\s+)%i(\\s+)%i',bb),...
    sprintf('%i$1%i$2%i$3%i',bb+round(p.Results.epspad.*[-1,-1,1,1])));
  fh = fopen([FileName,'.eps'],'w');
  fwrite(fh,epsfile);
  fclose(fh);
end

% Compress the eps if requested
if p.Results.compress
  if exist('epscompress','file') ~= 3
    if ~any( strcmpi(p.UsingDefaults,'compress') )
      warning('matlabfrag:epscompress:NotFound',...
        ['Cannot find a compiled version of epscompress, thus the eps\n',...
        'file will not be compressed. To compile epscompress, in Matlab\n',...
        'navigate to the matlabfrag folder and run:\n',...
        '  >> mex -setup %% If mex hasn''t been setup before\n',...
        '  >> mex epscompress.c\n\n',...
        'Suppress this warning in the future by running:\n',...
        '  >> warning off matlabfrag:epscompress:NotFound\n',...
        'or turning the ''compress'' option off.']);
    end
  else
    movefile([FileName,'.eps'],[FileName,'-uncompressed.eps']);
    epscompress([FileName,'-uncompressed.eps'],[FileName,'.eps']);
    delete([FileName,'-uncompressed.eps']);
  end
end

% Apply the undo action to restore the image to how
%  was originally
if p.Results.debuglvl >= STEP_THROUGH_ACTIONS
  disp('Starting to apply undo actions');
  for ii=UndoActions.length:-1:1
    fprintf(1,'Press space to unapply: %s\n',UndoActions.( ACTION_DESC_NAME(ii) ));
    pause;
    UndoActions.( ACTION_FUNC_NAME(ii) )();
  end
  disp('Finished applying undo actions');
else
  for ii=UndoActions.length:-1:1
    UndoActions.( ACTION_FUNC_NAME(ii) )();
  end
end

% Flush all drawing operations
drawnow;

% Sort by text size first
[Y,I] = sortrows( cell2mat( PsfragCmds(:,4) ) ); %#ok<*ASGLU> Required for backward compatibility
PsfragCmds = PsfragCmds(I,:);
% Now sort by colour
[Y,I] = sortrows( cell2mat( PsfragCmds(:,5) ), [3 2 1] );
PsfragCmds = PsfragCmds(I,:);
% Now sort by font angle
[Y,I] = sortrows( cell2mat( PsfragCmds(:,6) ) );
PsfragCmds = PsfragCmds(I,:);
% Now sort by font weight
[Y,I] = sortrows( cell2mat( PsfragCmds(:,7) ) );   
PsfragCmds = PsfragCmds(I,:);
% Now sort by whether it is 'fixed width'
[Y,I] = sortrows( cell2mat( PsfragCmds(:,8) ) );
PsfragCmds = PsfragCmds(I,:);
% Now sort by label type
[Y,I] = sortrows( PsfragCmds(:,9) );
PsfragCmds = PsfragCmds(I,:);
clear Y

% Finally write the latex-file
try
  fid = fopen([FileName,'.tex'],'w');
  fwrite(fid,TEXHDR);
  
  FontStylePrefix = 'matlabtext';
  FontStyleId = double('A')-1;
  NewFontStyle = 1;
  CurrentColour = [0 0 0];
  CurrentFontSize = 0;
  CurrentWeight = 0;
  CurrentAngle = 0;
  CurrentlyFixedWidth = 0;
  CurrentType = PsfragCmds{1,9};
  
  fprintf(fid,'\n%%');
  if strcmpi( p.Results.unaryminus, 'short' )
    writeOutNegTickShort(fid);
    writeOutNegTickShortScript(fid);
  end
  writeOutNegTickNoWidth(fid);
  
  fprintf(fid,'\n%%\n%%%% <%s>',CurrentType);
  for ii=1:size(PsfragCmds,1)
    % Test to see if the font size has changed
    if ~(CurrentFontSize == PsfragCmds{ii,4})
      CurrentFontSize = PsfragCmds{ii,4};
      NewFontStyle = 1;
    end
    % Test to see if the colour has changed
    if ~all(CurrentColour == PsfragCmds{ii,5})
      CurrentColour = PsfragCmds{ii,5};
      NewFontStyle = 1;
    end
    % Test to see if the font angle has changed
    if ~(CurrentAngle == PsfragCmds{ii,6})
      CurrentAngle = PsfragCmds{ii,6};
      NewFontStyle = 1;
    end
    % Test to see if the font weight has changed
    if ~(CurrentWeight == PsfragCmds{ii,7})
      CurrentWeight = PsfragCmds{ii,7};
      NewFontStyle = 1;
    end
    % Test to see if 'fixedwidth' has changed
    if ~(CurrentlyFixedWidth == PsfragCmds{ii,8})
      CurrentlyFixedWidth = PsfragCmds{ii,8};
      NewFontStyle = 1;
    end
    % Test to see if 'type' has changed
    if ~strcmpi(CurrentType,PsfragCmds{ii,9})
      fprintf(fid,'\n%%\n%%%% </%s>',CurrentType);
      CurrentType = PsfragCmds{ii,9};
      fprintf(fid,'\n%%\n%%%% <%s>',CurrentType);
      if ~NewFontStyle
        fprintf(fid,'\n%%');
      end
    end
    if NewFontStyle
      FontStyleId = FontStyleId + 1;
      if CurrentAngle; Angle = '\itshape';
      else Angle = ''; end;
      if CurrentWeight; Weight = '\bfseries\boldmath';
      else Weight = ''; end;
      if CurrentlyFixedWidth; Fixed = '\ttfamily';
      else Fixed = ''; end;
      fprintf(fid,['\n%%\n\\providecommand\\%s%s{\\color[rgb]{%.3f,%.3f,'...
        '%.3f}\\fontsize{%.2f}{%.2f}%s%s%s\\selectfont\\strut}%%'],FontStylePrefix,...
        char(FontStyleId),CurrentColour(1),CurrentColour(2),...
        CurrentColour(3),CurrentFontSize,CurrentFontSize,Angle,Weight,Fixed);
      NewFontStyle = 0;
    end
    fprintf(fid,'\n\\psfrag{%s}',PsfragCmds{ii,2});
    % Only put in positioning information if it is not [bl] aligned
    if ~strcmp(PsfragCmds{ii,3},'bl') || ~strcmp(PsfragCmds{ii,3},'lb')
      fprintf(fid,'[%s][%s]',PsfragCmds{ii,3},PsfragCmds{ii,3});
    end
    fprintf(fid,'{\\%s%s %s}%%',FontStylePrefix,...
      char(FontStyleId),RemoveSpaces(PsfragCmds{ii,1}));
  end
  fprintf(fid,'\n%%\n%%%% </%s>',CurrentType);
  
  fclose(fid);
  
catch                %#ok -- needed for r2007a support
  err = lasterror;   %#ok
  if fid > 0
    fclose(fid);
  end
  err.stack.line
  rethrow( err );
end
% All done! Below are the sub-functions

% Find all of the 'text' and 'axes' objects in the
% figure and dispatch the processing of them
  function ProcessFigure(parent)
    
    % Show all of the hidden handles
    hidden = get(0,'showhiddenhandles');
    set(0,'showhiddenhandles','on');
    
    % Get all text and axes handles
    axeshandles = findobj(parent,'Type','axes','visible','on');
    legendhandles = findobj(parent,'Type','axes','Tag','legend','visible','on');
    axeshandles = setdiff(axeshandles,legendhandles);
    texthandles = findobj(parent,'Type','text','visible','on');
    
    % Hide all of the hidden handles again
    set(0,'showhiddenhandles',hidden);
    
    % Get the position of all the text objects
    textpos = GetTextPos(texthandles);
    
    % Freeze all legends (after axes and legend listeners have been disables)
    for jj=1:length(legendhandles)
      ProcessLegends(legendhandles(jj));
    end
    
    % Freeze all axes, and process ticks.
    for jj=1:length(axeshandles)
      ProcessTicks(axeshandles(jj));
    end
    
    % Process all text.
    for jj=1:length(texthandles)
      ProcessText(texthandles(jj),textpos{jj});
    end
  end

% Get all fo the text object's positions.
  function TextPos = GetTextPos(texthandles)
    TextPos = cell(1,length(texthandles));
    for jj=1:length(texthandles)
      TextPos{jj} = get(texthandles(jj),'position');
      AddUndoAction('Reset text posision', @() set(texthandles(jj),'position', TextPos{jj} ));
    end
  end

% Process a text handle, extracting the appropriate data
%  and creating 'action' functions
  function ProcessText(handle,Pos)
    % Get some of the text properties.
    String = get(handle,'string');
    UserData = get(handle,'UserData');
    UserString = {};

    % Process the strings alignment options
    [halign,valign] = GetAlignment(handle);
    % Test to see if UserData is valid.
    if ischar(UserData)
      if ~isempty(sscanf(UserData,'%s'))
        UserString = regexp(UserData,[USERDATA_PREFIX,'(.*)'],'tokens');
      end
    end
    % Test for multiline strings (using cells).
    if iscell(String)
      % Error checking. Luckily Matlab is fairly nice with the way it
      % treats its strings in figures.
      assert( size(String,2) == 1 && iscellstr(String),...
        'matlabfrag:WeirdError',['Weird ''String'' formatting.\n',...
        'Please raise an issue on github (see the help text for a link),\n',...
        'as this error should not occur.']);
      % If the cell only has 1 element, then do nothing.
      if size(String,1)==1
        String = String{:};
      else
        temp = sprintf('\\begin{tabular}{@{}%c@{}}%s',halign,String{1});
        for jj=2:length(String)
          temp = sprintf('%s\\\\%s',temp,String{jj});
        end
        String = sprintf('%s\\end{tabular}',temp);
      end
    end
    % Test for multiline strings using matrices
    if size(String,1) > 1
      temp = sprintf('\\begin{tabular}{@{}%c@{}}%s',halign,...
        regexprep(String(1,:),' ','~'));
      for jj=2:size(String,1)
        temp = sprintf('%s\\\\%s',temp,...
          regexprep(String(jj,:),' ','~'));
      end
      String = sprintf('%s\\end{tabular}',temp);
    end
    % If there is no text, return.
    if isempty(sscanf(String,'%s')) && isempty(UserString); return; end;
    % Retrieve the common options
    [FontSize,FontAngle,FontWeight,FixedWidth] = CommonOptions(handle);
    % Assign a replacement action for the string
    CurrentReplacement = ReplacementString();
    SetUnsetProperties('Replacing text string',handle,'String',CurrentReplacement);
    % Check for a 'UserData' property, which replaces the string with latex
    if ~isempty(UserString)
      String = cell2mat(UserString{:});
    end
    % Replacement action for the interpreter
    if ~strcmpi(get(handle,'interpreter'),'none')
      SetUnsetProperties('Text Interpreter to none',handle,'interpreter','none');
    end
    % Make sure the final position is the same as the original one
    AddAction('Set text pos to where it originally was', @() set(handle,'position',Pos) );
    
    % Get the text colour
    Colour = get(handle,'color');
    % Finally create the replacement command
    AddPsfragCommand(String,CurrentReplacement,[valign,halign],...
      FontSize,Colour,FontAngle,FontWeight,FixedWidth,'text');
  end

% Process the legends. This should be done after the axes have been processed
%  and the legend listeners have been disabled.
  function ProcessLegends(handle)
    % Make sure legend ends up where it started from
    lpos = get(handle,'position');
    SetUnsetProperties('Legend Pos to current Pos',handle,'Position', lpos );
  end

% Processes the position, position mode and 'ticks' of an axis, then returns.
%  Don't do anything if it is a legend
  function ProcessTicks(handle)
    
    % Make sure figure doesn't resize itself while we are messing with it.
    for jj=['x' 'y' 'z']
      AutoTickLabel.(jj) = strcmpi(get(handle,[jj,'ticklabelmode']),'auto');
    end
    SetUnsetProperties('TickModes to manual',handle,...
      'xlimmode','manual','ylimmode','manual','zlimmode','manual',...
      'xtickmode','manual','ytickmode','manual','ztickmode','manual',...
      'xticklabelmode','manual','yticklabelmode','manual','zticklabelmode','manual');
    apos = get(handle,'position');
    SetUnsetProperties('Fix Axes Pos',handle,'position', apos );
    tickpropcell = {'xtick','ytick','ztick','xticklabel','yticklabel','zticklabel','xlim','ylim','zlim'};
    tickprops = get(handle,tickpropcell);
    varg = reshape( [ tickpropcell; tickprops ], 1, 2*length(tickprops) );
    SetUnsetProperties('Fix ticks',handle, varg{:} );
    try
      hlist = get(handle,'ScribeLegendListeners');
      SetUnsetProperties('Disable legend fontname listener',hlist.fontname,'enabled','off');
    catch                 %#ok -- required for r2007a support
      err = lasterror;    %#ok
      if ~isempty(regexpi(err.message,'''enabled'''))
        error('matlabfrag:legendlistener',...
          ['Oops, it looks like Matlab has changed the way it does legend\n',...
          'callbacks. Please let me know if you see by raising an issue\n',...
          'on github (see the help text for a link).']);
      end
    end
    % Extract common options.
    [FontSize,FontAngle,FontWeight,FixedWidth] = CommonOptions(handle);
    SetUnsetProperties('Axes font to fixed-width',handle,'FontName','fixedwidth');
    FontName = 'fixedwidth';
    % Test to see if the plot is 2D or 3D.
    Plot2D = isempty(get(handle,'zticklabel')) && all( get(handle,'view') == [0 90] );
    % Loop through all axes
    for jj = ['x' 'y' 'z']
      ticklabels = get(handle,[jj,'ticklabel']);
      ticks = get(handle,[jj,'tick']);
      lims = get(handle,[jj,'lim']);
      % If there are no ticks, skip to the next axis
      if isempty(ticks)
        continue;
      end
      % Trim the ticks (if they lay outside lims)
      if AutoTickLabel.(jj)
        ticks = ticks( ticks >= lims(1) );
        ticks = ticks( ticks <= lims(2) );
        SetUnsetProperties('Trimming tick labels',handle,[jj,'tick'],ticks);
      end
      set(handle,[jj,'tickmode'],'manual',[jj,'ticklabelmode'],'manual');
      if ~isempty(ticklabels)
        tickcolour = get(handle,[jj,'color']);
        
        % Test to see if it is on a logarithmic scale
        if strcmpi(get(handle,[jj,'scale']),'log') && AutoTickLabel.(jj)
          % And all of the values are integers
          ticklabelcell = mat2cell(ticklabels,ones(1,size(ticklabels,1)),size(ticklabels,2));
          if all(~isnan(str2double(ticklabelcell)))
            % If so, make the labels read 10^<TickLabel>
            if strcmpi( p.Results.unaryminus, 'short' )
              ticklabels = cellfun(@(x) ['$10^{',...
                regexprep( RemoveSpaces(x), '-', ['\\',NEGTICK_SHORT_SCRIPT_COMMAND,' '] ),...
                '}$'],ticklabelcell,'uniformoutput',0);
            else
              ticklabels = cellfun(@(x) ['$10^{',RemoveSpaces(x),...
                '}$'],ticklabelcell,'uniformoutput',0);
            end
          end
          
          % Test to see if there is a common factor
        elseif strcmpi(get(handle,[jj,'scale']),'linear') && AutoTickLabel.(jj)
          for kk=1:size(ticklabels,1)
            % Find the first non-NaN ratio between tick labels and tick
            % values
            scale = ticks(kk)/str2double(ticklabels(kk,:));
            if ~isnan(scale); break; end;
          end
          
          % If the scale is not 1, then we need to place a marker near the
          % axis
          if abs(scale-1) > 1e-3
            scale = log10(scale);
            % Make sure it is an integer.
            assert( abs(scale-round(scale))<1e-2, 'matlabfrag:AxesScaling:NonInteger',...
              ['Non integer axes scaling.  This is most likely a bug in matlabfrag.\n',...
              'Please let me know the ytick and yticklabel values for this plot.']);
            if strcmpi( p.Results.unaryminus, 'short' )
              LatexScale = ['$\times10^{', regexprep( num2str(round(scale)), '-', ['\\',NEGTICK_SHORT_SCRIPT_COMMAND,' '] ), '}$'];
            else
              LatexScale = ['$\times10^{',num2str(round(scale)),'}$'];
            end
            % Different action depending if the plot is 2D or 3D
            if Plot2D
              %2D Plot... fairly easy.
              % Common required data...
              Xlims = get(handle,'xlim');
              Ylims = get(handle,'ylim');
              Xdir = get(handle,'xdir');
              Ydir = get(handle,'ydir');
              XAlignment = get(handle,'XAxisLocation');
              YAlignment = get(handle,'YAxisLocation');
              % 2D plot, so only x and y...
              CurrentReplacement = ReplacementString();
              
              % If the axes are reversed, reverse the lims
              if strcmpi(Xdir,'reverse')
                Xlims = Xlims(end:-1:1);
              end
              if strcmpi(Ydir,'reverse')
                Ylims = Ylims(end:-1:1);
              end
                          
              % X axis scale
              if strcmpi(jj,'x')
                if strcmpi(XAlignment,'bottom');
                  ht = text(Xlims(2),Ylims(1),CurrentReplacement,...
                    'fontsize',FontSize,'fontname',FontName,...
                    'HorizontalAlignment','center','VerticalAlignment','top',...
                    'parent',handle,'interpreter','none');
                  extent = get(ht,'extent');
                  position = get(ht,'position');
                  set(ht,'position',[position(1) position(2)-1.0*extent(4) position(3)]);
                  Alignment = 'tc';
                else
                  ht = text(Xlims(2),Ylims(2),CurrentReplacement,...
                    'fontsize',FontSize,'fontname',FontName,...
                    'HorizontalAlignment','center','VerticalAlignment','bottom',...
                    'parent',handle,'interpreter','none');
                  extent = get(ht,'extent');
                  position = get(ht,'position');
                  set(ht,'position',[position(1) position(2)+1.0*extent(4) position(3)]);
                  Alignment = 'bc';
                end
                
                % Y axis scale
              else
                if strcmpi(XAlignment,'bottom')
                  if strcmpi(YAlignment,'left')
                    ht = text(Xlims(1),Ylims(2),CurrentReplacement,...
                      'fontsize',FontSize,'fontname',FontName,...
                      'HorizontalAlignment','center','VerticalAlignment','bottom',...
                      'parent',handle,'interpreter','none');
                  else
                    ht = text(Xlims(2),Ylims(2),CurrentReplacement,...
                      'fontsize',FontSize,'fontname',FontName,...
                      'HorizontalAlignment','center','VerticalAlignment','bottom',...
                      'parent',handle,'interpreter','none');
                  end
                  extent = get(ht,'extent');
                  position = get(ht,'position');
                  set(ht,'position',[position(1) position(2)+0.5*extent(4) position(3)]);
                  Alignment = 'bc';
                else
                  if strcmpi(YAlignment,'left')
                    ht = text(Xlims(1),Ylims(1),CurrentReplacement,...
                      'fontsize',FontSize,'fontname',FontName,...
                      'HorizontalAlignment','center','VerticalAlignment','top',...
                      'parent',handle,'interpreter','none');
                  else
                    ht = text(Xlims(2),Ylims(1),CurrentReplacement,...
                      'fontsize',FontSize,'fontname',FontName,...
                      'HorizontalAlignment','center','VerticalAlignment','top',...
                      'parent',handle,'interpreter','none');
                  end
                  extent = get(ht,'extent');
                  position = get(ht,'position');
                  set(ht,'position',[position(1) position(2)-0.5*extent(4) position(3)]);
                  Alignment = 'tc';
                end
              end
              
              % Create the replacement command
              AddPsfragCommand(LatexScale,CurrentReplacement,Alignment,FontSize,...
                tickcolour,FontAngle,FontWeight,FixedWidth,[jj,'scale']);
              % Delete the label
              AddUndoAction('Delete axis scale', @() delete(ht) );
            else
              % Why is this so hard?
              warning('matlabfrag:scaled3Daxis',...
                ['It looks like your %s axis is scaled on a 3D plot. Unfortunately\n',...
                'these are very hard to handle, so there may be a problem with\n',...
                'its placement. If you know of a better algorithm for placing it,\n',...
                'please let me know by creating an issue at www.github.com/zprime/matlabfrag',...
                ],jj);
              % :-(
              CurrentReplacement = ReplacementString();
              Xlim = get(handle,'xlim');
              Ylim = get(handle,'ylim');
              Zlim = get(handle,'zlim');
              axlen = @(x) x(2)-x(1);
              switch lower( jj )
                case 'x'
                  ht = text(Xlim(1)+0.6*axlen(Xlim),...
                    Ylim(1)-0.3*axlen(Ylim),...
                    Zlim(1),...
                    CurrentReplacement,'fontsize',FontSize,...
                    'fontname',FontName,'parent',handle,'interpreter','none');
                  Alignment = 'bl';
                case 'y'
                  ht = text(Xlim(1)-0.3*axlen(Xlim),...
                    Ylim(1)+0.6*axlen(Ylim),...
                    Zlim(1),...
                    CurrentReplacement,'fontsize',FontSize,...
                    'fontname',FontName,'horizontalalignment',...
                    'right','parent',handle,'interpreter','none');
                  Alignment = 'br';
                case 'z'
                  ht = text(Xlim(1),Ylim(2),Zlim(2)+0.2*axlen(Zlim),...
                    CurrentReplacement,'fontsize',FontSize,...
                    'fontname',FontName,'horizontalalignment',...
                    'right','parent',handle,'interpreter','none');
                  Alignment = 'br';
                otherwise
                  error('matlabfrag:wtf',['Bad axis; this error shouldn''t happen.\n',...
                    'please report it as a bug.']);
              end
              % Create the replacement command
              AddPsfragCommand(LatexScale,CurrentReplacement,Alignment,FontSize,...
                tickcolour,FontAngle,FontWeight,FixedWidth,[jj,'scale']);
              % Delete the label
              AddUndoAction('DeleteAxesScale', @() delete(ht) );
            end
          end
        end
        
        % Test whether all of the ticks are numbers, if so, substitute in
        % proper minus signs.
        if ~iscell(ticklabels)
          ticklabels = mat2cell(ticklabels,ones(1,size(ticklabels,1)),size(ticklabels,2));
        end
        TicksAreNumbers = 1;
        for kk=1:size(ticklabels,1)
          if isempty(ticklabels{kk,:})
            continue;
          end
          if isnan(str2double(ticklabels{kk,:}))
            TicksAreNumbers = 0;
            break;
          end
        end
        if TicksAreNumbers
          if (Plot2D && strcmpi(jj,'x')) || (~Plot2D && any(strcmpi(jj,{'x','y'})) )
            for kk=1:size(ticklabels)
              if isempty(ticklabels{kk,:})
                continue;
              end
              ticklabels{kk,:} = ['$',...
              RemoveSpaces( regexprep(ticklabels{kk,:},'-',['\\',NEGTICK_NO_WIDTH_COMMAND,' ']) ),...
              '$'];
            end
          else
            for kk=1:size(ticklabels)
              if isempty(ticklabels{kk,:})
                continue;
              end
              if strcmpi( p.Results.unaryminus, 'short' )
                ticklabels{kk,:} = ['$',...
                  RemoveSpaces( regexprep(ticklabels{kk,:},'-',['\\',NEGTICK_SHORT_COMMAND,' ']) ),...
                  '$'];
              else
                ticklabels{kk,:} = ['$', RemoveSpaces( ticklabels{kk,:} ),'$'];
              end
            end
          end
        end
        clear TicksAreNumbers
        
        tickreplacements = cell(1,size(ticklabels,1));
        % Process the X and Y tick alignment
        if ~strcmpi(jj,'z')
          switch get(handle,[jj,'axislocation'])
            case 'left'
              tickalignment = 'rc';
            case 'right'
              tickalignment = 'lc';
            case 'bottom'
              tickalignment = 'ct';
            case 'top'
              tickalignment = 'cb';
            otherwise
              tickalignment = 'cr';
              warning('matlabfrag:UnknownAxisLocation',...
                'Unknown axis location defaulting to ''cr''');
          end
        else
        % Fixed Z tick alignment
          tickalignment = 'cr';
        end
        
        % Now process the actual tick labels themselves...
        for kk=1:size(ticklabels,1)
          if isempty( ticklabels{kk,:} )
            tickreplacements{kk} = '';
            continue;
          end
          tickreplacements{kk} = ReplacementString();
          AddPsfragCommand(ticklabels{kk,:},tickreplacements{kk},...
            tickalignment,FontSize,tickcolour,FontAngle,FontWeight,...
            FixedWidth,[jj,'tick']);
        end
        % Now add the replacement action...
        SetUnsetProperties('Tick replacement',handle,[jj,'ticklabel'],tickreplacements);
      end
    end
  end    % of ProcessTicks

% Get the next replacement string
  function CurrentReplacement = ReplacementString()
    CurrentReplacement = sprintf(REPLACEMENT_FORMAT,StringCounter);
    StringCounter = StringCounter+1;
  end

% Extract and process the options that are common to text labels as
% well as axes ticks
  function [FontSize,FontAngle,FontWeight,FixedWidth] = CommonOptions(handle)
    % First get the fontsize (making sure it is in points)
    temp_prop = get(handle,'FontUnits');
    if ~strcmpi(temp_prop,'points')
      SetUnsetProperties('FontUnits to points',handle,'FontUnits','points');
    end
    FontSize = get(handle,'FontSize');
% %     SetUnsetProperties('FontSize to 10',handle,'Fontsize',10);
    % Now get the font angle (read - italics)
    switch get(handle,'FontAngle')
      case 'normal'
        FontAngle = 0;
      case 'italic'
        FontAngle = 1;
      case 'oblique'
        warning('matlabfrag:ObliqueFont',...
          'Nobody in their right mind uses Oblique font. Defaulting to italic.');
        FontAngle = 1;
      otherwise
        warning('matlabfrag:UnknownFontType',...
          'Unknown FontAngle for the string "%s"',get(handle,'String'));
        FontAngle = 0;
    end
% %     if FontAngle
% %       SetUnsetProperties('FontAngle to normal',handle,'FontAngle','normal');
% %     end
    % Now get the FontWeight (read - bold)
    switch get(handle,'FontWeight')
      case 'light'
        warning('matlabfrag:LightFontNotSupported',...
          'Light FontWeight does not really translate to LaTeX... Defaulting to normal.');
        FontWeight = 0;
      case 'normal'
        FontWeight = 0;
      case 'demi'
        warning('matlabfrag:DemiFontNotSupported',...
          'Demi FontWeight does not really translate to LaTeX... Defaulting to normal.');
        FontWeight = 0;
      case 'bold'
        FontWeight = 1;
      otherwise
        warning('matlabfrag:UnknownFontWeight',...
          'Unknown FontWeight for the string %s',get(handle,'String'));
    end
% %     if FontWeight
% %       SetUnsetProperties('FontWeight to normal',handle,'FontWeight','normal');
% %     end
    % Test to see if the font is 'fixed width'
    if strcmpi(get(handle,'FontName'),'FixedWidth')
      FixedWidth = 1;
    else
      FixedWidth = 0;
    end
% %     if ~FixedWidth
% %       SetUnsetProperties('Set text to FixedWidth',handle,'FontName','fixed-width');
% %     end
  end

% Adds a PsFrag command to the cell. This is a function to ensure allow a
%  standard calling convention to be established.
  function AddPsfragCommand(LatexString,ReplacementString,Alignment,...
      FontSize,Colour,FontAngle,FontWeight,FixedWidth,Type)
    PsfragCmds(size(PsfragCmds,1)+1,:) = {LatexString,ReplacementString,...
      Alignment,FontSize,Colour,FontAngle,FontWeight,FixedWidth,Type};
  end

% Set and then unset some handle properties using 'Actions' and
% 'UndoActions'
  function SetUnsetProperties(description,handle,varargin)
    Props = varargin(1:2:end);
    PropVals = varargin(2:2:end);
    TempPropVals = get(handle,Props);
    AddAction(description, @() set(handle,Props,PropVals) );
    AddUndoAction(description, @() set(handle,Props,TempPropVals) );
  end

% Add an 'action' function to the list of actions to perform before the
%  image is saved.
  function AddAction(description,action)
    Actions.length = Actions.length + 1;
    Actions.( ACTION_FUNC_NAME( Actions.length ) ) = action;
    Actions.( ACTION_DESC_NAME( Actions.length ) ) = description;
  end

% Adds an 'undo-action' function to the list... these get processed after
%  the image has been saved, to restore the screen state.
  function AddUndoAction(description,action)
    UndoActions.length = UndoActions.length + 1;
    UndoActions.( ACTION_FUNC_NAME( UndoActions.length ) ) = action;
    UndoActions.( ACTION_DESC_NAME( UndoActions.length ) ) = description;
  end

% Remove leading and trailing edge white spaces
% from any string.
  function cropped_string = RemoveSpaces(string)
    if iscell(string)
      string = string{:};
    end
    if isempty( string )
      cropped_string = string;
      return;
    end
    if all( string == ' ' )
      cropped_string = '';
      return;
    end
    I = regexp(string,'[^\s]');
    cropped_string = string(I(1):I(end));
    if cropped_string(end) == '\'
      cropped_string = [ cropped_string, ' ' ];
    end
  end

  function [halign,valign] = GetAlignment(handle)
    HAlign = get(handle,'HorizontalAlignment');
    switch HAlign
      case 'left'
        halign = 'l';
      case 'right'
        halign = 'r';
      case 'center'
        halign = 'c';
      otherwise
        warning('matlabfrag:UnknownHorizAlign',...
          'Unknown text horizontal alignment for "%s", defaulting to left',string);
        halign = 'l';
    end
    VAlign = get(handle,'VerticalAlignment');
    switch VAlign
      case {'baseline'}
        valign = 'B';
      case {'bottom','base'}
        valign = 'b';
      case {'top','cap'}
        valign = 't';
      case {'middle'}
        valign = 'c';
      otherwise
        warning('matlabfrag:UnknownVertAlign',...
          'Unknown text vertical alignment for "%s", defaulting to bottom',string);
        valign = 'b';
    end
  end

% Busy waits for a file to finish being created. This is necessary because
% on some platforms the file isn't available immediately after performing a
% print.
  function FileWait(filename)
    counter = 0;
    while ~exist(filename,'file')
      pause(0.05);
      assert( counter < 100, 'matlabfrag:filetimeout',...
        'File Timeout. This occured after printing %s and trying to then read it.',filename);
      counter = counter + 1;
    end
  end
% Print two versions of the file, one renderered with the renderer of
% choice, and another rendererd with painters. Then perform some epscombine
% magic to recombine them.
  function EpsCombine(handle,renderer,filename,dpiswitch,keep_tempfile)
    TEXTOBJ_REGEXP = ['-?\d+\s+-?\d+\s+mt(\s+-?\d+\s+rotate)?',...
      '\s+\(.+?\)\s+s',...
      '(\s+-?\d+\s+rotate)?'];
    TEXTHDR_REGEXP = '%%IncludeResource:\s+font.*?\n.?\n';
    if keep_tempfile
      tmp_file = [filename,'-painters'];
    else
      tmp_file = tempname;
    end
    
    % Show all of the hidden handles
    hidden = get(0,'showhiddenhandles');
    set(0,'showhiddenhandles','on');
    
    ht = findobj(handle,'type','text');
    ht = findobj(ht,'visible','on');
    
    % Handles of objects marked with matlabfrag:painters
    hv = findobj(handle,'userdata','matlabfrag:painters');
    ht = union( ht, hv );
    
    ha = findobj(handle,'type','axes');
    
    % Hide all of the text handles again
    set(0,'showhiddenhandles',hidden);
    
    % Make the text invisible
    set(ht,'visible','off');
    hnam = @(x) ['h',num2str(x)];
    for jj=1:length(ha)
      tickvals.(hnam(jj)).xtl = get(ha(jj),'xticklabel');
      tickvals.(hnam(jj)).ytl = get(ha(jj),'yticklabel');
      tickvals.(hnam(jj)).ztl = get(ha(jj),'zticklabel');
      set(ha(jj),'xticklabel','','yticklabel','','zticklabel','');
    end
    % Now print it.
    drawnow;
    print(handle,'-depsc2','-loose',dpiswitch,...
      ['-',renderer],filename);
    FileWait([filename,'.eps']);
    % Restore the text
    set(ht,'visible','on');
    for jj=1:length(ha)
      set(ha(jj),'xticklabel',tickvals.(hnam(jj)).xtl);
      set(ha(jj),'yticklabel',tickvals.(hnam(jj)).ytl);
      set(ha(jj),'zticklabel',tickvals.(hnam(jj)).ztl);
    end
    % Now print a painters version.
    drawnow;
    print(handle,'-depsc2','-loose',dpiswitch,...
      '-painters',tmp_file);
    FileWait([tmp_file,'.eps']);
    % Open it up and extract the text
    try
      fh = fopen([tmp_file,'.eps'],'r');
      paintersfile = fread(fh,inf,'uint8=>char').';
      fh = fclose(fh);
    catch                  %#ok -- required for r2007a support
      err = lasterror;     %#ok
      if fh > 0
        fh = close(fh);
      end
      rethrow( err );
    end
    if ~keep_tempfile
      delete([tmp_file,'.eps']);
    end
    textobj = regexpi(paintersfile,TEXTOBJ_REGEXP,'match');
    textobjpos = regexpi(paintersfile,TEXTOBJ_REGEXP);
    texthdr = regexpi(paintersfile,TEXTHDR_REGEXP,'match');
    texthdrpos = regexpi(paintersfile,TEXTHDR_REGEXP);
    textData = cell(length(textobjpos)+length(texthdrpos),2);
    textData(:,1) = num2cell([texthdrpos.';textobjpos.']);
    textData(:,2) = [texthdr,textobj].';
    [Ysort,Isort] = sortrows( cell2mat( textData(:,1) ) );
    textData = textData(Isort,:);
    
    % Open up the target file, and read the contents.
    try
      fh = fopen([filename,'.eps'],'r');
      epsfile = fread(fh,inf,'uint8=>char').';
      fh = fclose(fh);
    catch                  %#ok -- this is required for r2007a support
      err = lasterror;     %#ok
      if fh > 0
        fh = close(fh);
      end
      rethrow( err );
    end
    % Insert the new text
    findex = regexp(epsfile,'end %%Color Dict');
    epsfile = sprintf('%s\n\n%s\n%s',...
      epsfile(1:findex-1),...
      sprintf('%s\n',textData{:,2}),...
      epsfile(findex:end));
    try
      fh = fopen([filename,'.eps'],'w');
      fwrite(fh,epsfile);
      fh = fclose(fh);
    catch                %#ok -- this is required for r2007a support
      err = lasterror;   %#ok
      if fh > 0
        fh = fclose(fh);
      end
      rethrow( err );
    end
  end

% Test to see if there is any text in the figure
  function NoText = FigureHasNoText(p)
    NoText = 0;
    
    hidden = get(0,'showhiddenhandles');
    set(0,'showhiddenhandles','on');
    tempht = findobj(p.Results.handle,'type','text','visible','on');
    tempha = findobj(p.Results.handle,'type','axes','visible','on');
    set(0,'showhiddenhandles',hidden);
 
    for kk=tempht.'
      temptext = get(kk,'string');
      if ischar(temptext)
        temptext = mat2cell(temptext,ones(1,size(temptext,1)));
      end
      if isempty( regexp( temptext, '\S', 'once' ));
        tempht = setxor(tempht,kk);
      end
    end
    
    for kk=tempha.'
      if isempty( get(kk,'xticklabel') )
        if isempty( get(kk,'yticklabel') )
          if isempty( get(kk,'zticklabel') )
            tempha = setxor(tempha,kk);
          end
        end
      end
    end
    
    if isempty(tempht) && isempty(tempha)
      % No Text! Why are you using this then?
      warning('matlabfrag:noText',['No text in image. You would be better off ',...
        'using a function like <a href="matlab:web(''http://www.mathworks.com',...
        '/matlabcentral/fileexchange/10889'',''-browser'')">savefig</a>.\n',...
        '.tex file will not be created.']);
      
      % Set up the figure
      OrigUnits = get(p.Results.handle,'units');
      set(p.Results.handle,'units','centimeters');
      Pos = get(p.Results.handle,'position');
      OrigPPos = get(p.Results.handle,{'paperunits','paperposition'});
      set(p.Results.handle,'paperunits','centimeters','paperposition',Pos);
      
      % Test to see if the directory (if specified) exists
      [pathstr,namestr] = fileparts(p.Results.FileName);
      if ~isempty(pathstr)
        if ~exist(['./',pathstr],'dir')
          mkdir(pathstr);
        end
        % Tidy up the FileName
        FileName = [pathstr,filesep,namestr];
      else
        FileName = namestr;
      end
      
      % Print the image
      print(p.Results.handle,'-depsc2',['-',p.Results.renderer],...
        sprintf('-r%i',p.Results.dpi),'-loose',FileName);
      
      % Restore the figure
      set(p.Results.handle,'units',OrigUnits,'paperunits',...
        OrigPPos{1},'paperposition',OrigPPos{2});
      
      NoText = 1;
    end
  end

end % of matlabfrag(FileName,p.Results.handle)

% Copyright (c) 2008--2013, Zebb Prime
% All rights reserved.
% 
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions are met:
%     * Redistributions of source code must retain the above copyright
%       notice, this list of conditions and the following disclaimer.
%     * Redistributions in binary form must reproduce the above copyright
%       notice, this list of conditions and the following disclaimer in the
%       documentation and/or other materials provided with the distribution.
%     * Neither the name of the organization nor the
%       names of its contributors may be used to endorse or promote products
%       derived from this software without specific prior written permission.
% 
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
% ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
% WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
% DISCLAIMED. IN NO EVENT SHALL ZEBB PRIME BE LIABLE FOR ANY
% DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
% (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
% ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
% (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
% SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.