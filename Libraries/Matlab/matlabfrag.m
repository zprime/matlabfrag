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
%    'renderer'    | ['painters','opengl','zbuffer'] - The renderer used
%                  |  to generate the figure. The default is 'painters'.
%                  |  If you have manually specified the renderer,
%                  |  matlabfrag will use this value.
%    'dpi'         | DPI to print the images at. Default is 300. Note that
%                  |  this option has little effect when using 'painters'
%
% EXAMPLE
% plot(1:10,rand(1,10));
% set(gca,'FontSize',8);
% title('badness $\phi$','interpreter','latex','fontweight','bold');
% xlabel('1 to 10','userdata','matlabfrag:\macro');
% ylabel('random','fontsize',14);
% matlabfrag('RandPlot','epspad',[5,0,0,0]);
%
% v0.6.3 08-Jul-2009
%
% Please report bugs to zebb.prime+matlabfrag@gmail.com
%
% Available from the Matlab File Exchange

function matlabfrag(FileName,varargin)

% Matlab version check
v = version;
v = sscanf(v,'%i.%i');
v = eval( sprintf('%i.%i',v(1),v(2)) );
if v < 7.4
  error('matlabfrag:oldMatlab','Matlabfrag requires Matlab r2007a or newer to run');
end

% Version information is taken from the above help information
HelpText = help('matlabfrag');
LatestVersion = regexp(HelpText,'(v[\d\.]+) ([\d]+\-[\w]+\-[\d]+)','tokens');
LatestVersion = LatestVersion{1};
Version = LatestVersion{1};
VersionDate = LatestVersion{2};
TEXHDR = sprintf('%% Generated using matlabfrag\n%% Version: %s\n%% Version Date: %s\n%% Author: Zebb Prime',...
  Version,VersionDate);

% Global macros
REPLACEMENT_FORMAT = '%03d';
USERDATA_PREFIX = 'matlabfrag:';

% Debug macro levels
KEEP_TEMPFILE = 1;
PAUSE_BEFORE_PRINT = 2;
PAUSE_AFTER_PRINT = 2;
STEP_THROUGH_ACTIONS = 3;

p = inputParser;
p.FunctionName = 'matlabfrag';

p.addRequired('FileName', @(x) ischar(x) );
p.addOptional('handle', gcf, @(x) ishandle(x) && strcmpi(get(x,'Type'),'figure') );
p.addOptional('epspad', [0,0,0,0], @(x) isnumeric(x) && (all(size(x) == [1 4])) );
p.addOptional('renderer', 'painters', ...
    @(x) any( strcmpi(x,{'painters','opengl','zbuffer'}) ) );
p.addOptional('dpi', 300, @(x) isnumeric(x) );
p.addOptional('debuglvl',0, @(x) isnumeric(x) && x>=0);
p.parse(FileName,varargin{:});

Actions = {};
UndoActions = {};
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
SetUnsetProperties(p.Results.handle,'PaperUnits','centimeters',...
  'PaperPosition',Pos);

% Show all of the hidden handles
hidden = get(0,'showhiddenhandles');
set(0,'showhiddenhandles','on');

% Process the picture
ProcessFigure(p.Results.handle);

% Apply the actions resulting from the processing
if p.Results.debuglvl >= STEP_THROUGH_ACTIONS
  disp('Starting to apply actions');
  for ii=1:length(Actions)
    Actions{ii}();
    pause;
  end
  disp('Finished applying actions');
else
  for ii=1:length(Actions)
    Actions{ii}();
  end
end

if p.Results.debuglvl >= PAUSE_BEFORE_PRINT
  disp('Paused before printing');
  pause;
end

% Test to see if the directory (if specified) exists
[pathstr,namestr] = fileparts(FileName);
if ~isempty(pathstr)
  if ~exist(['./',pathstr],'dir')
    mkdir(pathstr);
  end
  % Tidy up the FileName
  FileName = [pathstr,filesep,namestr];
else
  FileName = namestr;
end

dpiswitch = ['-r',num2str( round( p.Results.dpi ) )];
% Unless over-ridden, check to see if 'renderermode' is 'manual'
renderer = p.Results.renderer;
if any( strcmpi(p.UsingDefaults,'renderer') )
  if strcmpi(get(p.Results.handle,'renderermode'),'manual')
    renderer = get(p.Results.handle,'renderer');
  end
end

if strcmpi(renderer,'painters')
  % Export the image to an eps file
  drawnow;
  print(p.Results.handle,'-depsc2','-loose',dpiswitch,'-painters',FileName);
else
  % If using the opengl or zbuffer renderer
  EpsCombine(p.Results.handle,renderer,FileName,dpiswitch,...
    p.Results.debuglvl>=KEEP_TEMPFILE)
end

if p.Results.debuglvl >= PAUSE_AFTER_PRINT
  disp('Paused after printing');
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

% Apply the undo action to restore the image to how
%  was originally
if p.Results.debuglvl >= STEP_THROUGH_ACTIONS
  disp('Starting to apply undo actions');
  for ii=1:length(UndoActions)
    UndoActions{ii}();
    pause;
  end
  disp('Finished applying undo actions');
else
  for ii=1:length(UndoActions)
    UndoActions{ii}();
  end
end
% Hide all of the hidden handles again
set(0,'showhiddenhandles',hidden);

% Flush all drawing operations
drawnow;

% Test to see if there is any text
if isempty( PsfragCmds )
  warning('matlabfrag:noText',...
    ['It appears your figure does not contain any text. It is probably\n',...
     'better to use a function that just exports the figure in this',...
     'case (e.g.\nthe ''print'' command).\n',...
     'Matlabfrag will now print the eps file, but not write a tex file.']);
  return;
end

% Sort by text size first
[Y,I] = sortrows(char(PsfragCmds{:,4}));
PsfragCmds = PsfragCmds(I,:);
% Now sort by colour
[Y,I] = sortrows(char(PsfragCmds{:,5}),[3 2 1]);
PsfragCmds = PsfragCmds(I,:);
% Now sort by font angle
[Y,I] = sortrows(char(PsfragCmds{:,6}));
PsfragCmds = PsfragCmds(I,:);
% Now sort by font weight
[Y,I] = sortrows(char(PsfragCmds{:,7}));
PsfragCmds = PsfragCmds(I,:);
% Now sort by whether it is 'fixed width'
[Y,I] = sortrows(char(PsfragCmds{:,8}));
PsfragCmds = PsfragCmds(I,:);
% Now sort by label type
[Y,I] = sortrows(char(PsfragCmds{:,9}));
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
    % Test to see fi the font angle has changed
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
        '%.3f}\\fontsize{%d}{%d}%s%s%s\\selectfont}%%'],FontStylePrefix,...
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

catch err
  if fid > 0
    fclose(fid);
  end
  err.stack.line
  rethrow(err);
end
% All done! Below are the sub-functions

% Find all of the 'text' and 'axes' objects in the
% figure and dispatch the processing of them
  function ProcessFigure(parent)
    % Dispatcher to different processing types
    axeshandles = findobj(parent,'Type','axes');
    texthandles = findobj(parent,'Type','text');
    textpos = GetTextPos(texthandles);
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
      AddUndoAction( @() set(texthandles(jj),'position', TextPos{jj} ));
    end
  end

% Process a text handle, extracting the appropriate data
%  and creating 'action' functions
  function ProcessText(handle,Pos)
    % Get some of the text properties.
    String = get(handle,'string');
    UserData = get(handle,'UserData');
    UserString = {};
    % Test to see if the text is visible. If not, return.
    if strcmpi(get(handle,'visible'),'off'); return; end;
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
        'Please email the author, as this error should not occur.']);
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
    SetUnsetProperties(handle,'String',CurrentReplacement);
    % Check for a 'UserData' property, which replaces the string with latex
    if ~isempty(UserString)
      String = cell2mat(UserString{:});
    end
    % Replacement action for the interpreter
    if ~strcmpi(get(handle,'interpreter'),'none')
      SetUnsetProperties(handle,'interpreter','none');
    end
    % Make sure the final position is the same as the original one
    AddAction( @() set(handle,'position',Pos) );

    % Get the text colour
    Colour = get(handle,'color');
    % Finally create the replacement command
    AddPsfragCommand(String,CurrentReplacement,[valign,halign],...
      FontSize,Colour,FontAngle,FontWeight,FixedWidth,'text');
  end

% Processes the position, position mode and 'ticks' of an axis, then returns.
%  Don't do anything if it is a legend
  function ProcessTicks(handle)
    % Return if nothing to do.
    if strcmpi(get(handle,'visible'),'off'); return; end;
    % If legend, freeze the axes and return.
    if strcmpi(get(handle,'tag'),'legend');
      SetUnsetProperties(handle,'OuterPosition', get(handle,'OuterPosition') );
      SetUnsetProperties(handle,'ActivePositionProperty','OuterPosition');
      SetUnsetProperties(handle,'Position', get(handle,'Position') );
      return;
    end;
    % Make sure figure doesn't resize itself while we are messing with it.
    for jj=['x' 'y' 'z']
      AutoTick.(jj) = strcmpi(get(handle,[jj,'tickmode']),'auto');
      AutoTickLabel.(jj) = strcmpi(get(handle,[jj,'ticklabelmode']),'auto');
    end
    SetUnsetProperties(handle,'OuterPosition', get(handle,'OuterPosition') );
    SetUnsetProperties(handle,'ActivePositionProperty','Position');
    SetUnsetProperties(handle,'Position', get(handle,'Position') );
    SetUnsetProperties(handle,'xticklabelmode','manual','yticklabelmode',...
      'manual','zticklabelmode','manual');
    SetUnsetProperties(handle,'xlimmode','manual','ylimmode','manual','zlimmode','manual');
    SetUnsetProperties(handle,'xtickmode','manual','ytickmode','manual',...
      'ztickmode','manual');
    % Extract common options.
    [FontSize,FontAngle,FontWeight,FixedWidth] = CommonOptions(handle);
    try
      hlist = get(handle,'ScribeLegendListeners');
      SetUnsetProperties(hlist.fontname,'enabled','off');
    catch err
      if ~isempty(regexpi(err.message,'''enabled'''))
        error('matlabfrag:legendlistener',...
          ['Oops, it looks like Matlab has changed the way it does legend\n',...
           'callbacks. Please let me know if you see this via ',...
           '<a href="mailto:zebb.prime+matlabfrag@gmail.com?subject=',...
           'Matlabfrag:ScribeLegendListener_error">email</a>']); 
      end
    end
    SetUnsetProperties(handle,'fontname','fixedwidth');
    FontName = 'fixedwidth';
    % Change the font
    for jj = ['x' 'y' 'z']
      ticklabels = get(handle,[jj,'ticklabel']);
      ticks = get(handle,[jj,'tick']);
      set(handle,[jj,'tickmode'],'manual',[jj,'ticklabelmode'],'manual');
      if ~isempty(ticklabels)
        tickcolour = get(handle,[jj,'color']);

        % Test to see if it is on a logarithmic scale
        if strcmpi(get(handle,[jj,'scale']),'log') && AutoTickLabel.(jj)
          % And all of the values are integers
          ticklabelcell = mat2cell(ticklabels,ones(1,size(ticklabels,1)),size(ticklabels,2));
          if all(~isnan(str2double(ticklabelcell)))
            % If so, make the labels read 10^<TickLabel>
            ticklabels = cellfun(@(x) ['$10^{',x,'}$'], ticklabelcell,'uniformoutput',0);
          end

          % Test to see if there is a common factor
        elseif strcmpi(get(handle,[jj,'scale']),'linear') && AutoTick.(jj) && AutoTickLabel.(jj)
          for kk=1:size(ticklabels,1)
            % Find the first non-NaN ratio between tick labels and tick
            % values
            scale = ticks(kk)/str2double(ticklabels(kk,:));
            if ~isnan(scale); break; end;
          end

          % If the scale is not 1, then we need to place a marker near the
          % axis
          if abs(scale-1) > 1e-3
            LatexScale = ['$\times10^{',num2str(log10(scale)),'}$'];
            % Test to see if this is a 3D or 2D plot
            if isempty(get(handle,'zticklabel')) &&...
                all( get(handle,'view') == [0 90] )

              %2D Plot... fairly easy.
              % Common required data...
              Xlims = get(handle,'xlim');
              Ylims = get(handle,'ylim');
              XAlignment = get(handle,'XAxisLocation');
              YAlignment = get(handle,'YAxisLocation');
              % 2D plot, so only x and y...
              CurrentReplacement = ReplacementString();
              % Make the axis we are looking at the current one
              hCA = get(p.Results.handle,'CurrentAxes');
              set(p.Results.handle,'CurrentAxes',handle);

              % X axis scale
              if strcmpi(jj,'x')
                if strcmpi(XAlignment,'bottom');
                  ht = text(Xlims(2),Ylims(1),CurrentReplacement,...
                    'fontsize',FontSize,'fontname',FontName,...
                    'HorizontalAlignment','center','VerticalAlignment','top');
                  extent = get(ht,'extent');
                  position = get(ht,'position');
                  set(ht,'position',[position(1) position(2)-1.0*extent(4) position(3)]);
                  Alignment = 'tc';
                else
                  ht = text(Xlims(2),Ylims(2),CurrentReplacement,...
                    'fontsize',FontSize,'fontname',FontName,...
                    'HorizontalAlignment','center','VerticalAlignment','bottom');
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
                    'HorizontalAlignment','center','VerticalAlignment','bottom');
                  else
                    ht = text(Xlims(2),Ylims(2),CurrentReplacement,...
                    'fontsize',FontSize,'fontname',FontName,...
                    'HorizontalAlignment','center','VerticalAlignment','bottom');
                  end
                  extent = get(ht,'extent');
                  position = get(ht,'position');
                  set(ht,'position',[position(1) position(2)+0.5*extent(4) position(3)]);
                  Alignment = 'bc';
                else
                  if strcmpi(YAlignment,'left')
                    ht = text(Xlims(1),Ylims(1),CurrentReplacement,...
                    'fontsize',FontSize,'fontname',FontName,...
                    'HorizontalAlignment','center','VerticalAlignment','top');
                  else
                    ht = text(Xlims(2),Ylims(1),CurrentReplacement,...
                    'fontsize',FontSize,'fontname',FontName,...
                    'HorizontalAlignment','center','VerticalAlignment','top');
                  end
                  extent = get(ht,'extent');
                  position = get(ht,'position');
                  set(ht,'position',[position(1) position(2)-0.5*extent(4) position(3)]);
                  Alignment = 'tc';
                end
              end

              % Restore gca
              set(p.Results.handle,'CurrentAxes',hCA);
              % Create the replacement command
              AddPsfragCommand(LatexScale,CurrentReplacement,Alignment,FontSize,...
                tickcolour,FontAngle,FontWeight,FixedWidth,[jj,'scale']);
              % Delete the label
              AddUndoAction( @() delete(ht) );
            else
              % Why is this so hard?
              warning('matlabfrag:scaled3Daxis',...
                ['It looks like your %s axis is scaled on a 3D plot. Unfortunately\n',...
                'these are very hard to handle, so there may be a problem with\n',...
                'its placement. If you know of a better algorithm for placing it,\n',...
                'please let me know at zebb.prime+matlabfrag@gmail.com',...
                ],jj);
              % :-(
              % Make the axis we are looking at the current one
              hCA = get(p.Results.handle,'CurrentAxes');
              set(p.Results.handle,'CurrentAxes',handle);
              CurrentReplacement = ReplacementString();
              Xlim = get(gca,'xlim');
              Ylim = get(gca,'ylim');
              Zlim = get(gca,'zlim');
              axlen = @(x) x(2)-x(1);
              switch lower( jj )
                case 'x'
                  ht = text(Xlim(1)+0.6*axlen(Xlim),...
                    Ylim(1)-0.3*axlen(Ylim),...
                    Zlim(1),...
                    CurrentReplacement,'fontsize',FontSize,...
                      'fontname',FontName);
                  Alignment = 'bl';
                case 'y'
                  ht = text(Xlim(1)-0.3*axlen(Xlim),...
                    Ylim(1)+0.6*axlen(Ylim),...
                    Zlim(1),...
                    CurrentReplacement,'fontsize',FontSize,...
                      'fontname',FontName,'horizontalalignment',...
                      'right');
                  Alignment = 'br';
                case 'z'
                  ht = text(Xlim(1),Ylim(2),Zlim(2)+0.2*axlen(Zlim),...
                    CurrentReplacement,'fontsize',FontSize,...
                       'fontname',FontName,'horizontalalignment',...
                       'right');
                  Alignment = 'br';
                otherwise
                  error('matlabfrag:wtf',['Bad axis; this error shouldn''t happen.\n',...
                    'please report it as a bug.']);
              end
              % Restore gca
              set(p.Results.handle,'CurrentAxes',hCA);
              % Create the replacement command
              AddPsfragCommand(LatexScale,CurrentReplacement,Alignment,FontSize,...
                tickcolour,FontAngle,FontWeight,FixedWidth,[jj,'scale']);
              % Delete the label
              AddUndoAction( @() delete(ht) );
            end
          end
        end

        % Test whether all of the ticks are numbers, if so wrap them in $
        TicksAreNumbers = 1;
        for kk=1:size(ticklabels,1)
          if isnan(str2double(ticklabels(kk,:)))
            TicksAreNumbers = 0;
            break;
          end
        end
        if TicksAreNumbers
          if ~iscell(ticklabels)
            ticklabels = mat2cell(ticklabels,ones(1,size(ticklabels,1)),size(ticklabels,2));
          end
          ticklabels = cellfun(@(x) ['$', RemoveSpaces(x),'$'], ticklabels,'uniformoutput',0);
        end
        clear TicksAreNumbers

        tickreplacements = cell(1,size(ticklabels,1));
        % Process the X and Y tick alignment
        if ~strcmp(jj,'z')
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
        end

        % Now process the actual tick labels themselves...
        for kk=1:size(ticklabels,1)
          tickreplacements{kk} = ReplacementString();
          AddPsfragCommand(ticklabels(kk,:),tickreplacements{kk},...
            tickalignment,FontSize,tickcolour,FontAngle,FontWeight,...
            FixedWidth,[jj,'tick']);
        end
        % Now add the replacement action...
        SetUnsetProperties(handle,[jj,'ticklabel'],tickreplacements);
        if AutoTickLabel.(jj)
          AddUndoAction( @() set(handle, [jj,'ticklabelmode'],'auto'));
        end
      end
    end
  end

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
      set(handle,'FontUnits','points');
      FontSize = get(handle,'FontSize');
      set(handle,'FontUnits',temp_prop);
    else
      FontSize = get(handle,'FontSize');
    end
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
%     if FontAngle
%       SetUnsetProperties(handle,'FontAngle','normal');
%     end
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
%     if FontWeight
%       SetUnsetProperties(handle,'FontWeight','normal');
%     end
    % Test to see if the font is 'fixed width'
    if strcmpi(get(handle,'FontName'),'FixedWidth')
      FixedWidth = 1;
    else
      FixedWidth = 0;
    end
%     if FixedWidth
%       SetUnsetProperties(handle,'FontName','Helvetica');
%     end
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
  function SetUnsetProperties(handle,varargin)
    for jj=1:2:length(varargin)
      TempProp = get(handle,varargin{jj});
      AddAction( @() set(handle,varargin{jj},varargin{jj+1}) );
      AddUndoAction( @() set(handle,varargin{jj},TempProp) );
    end
  end

% Add an 'action' function to the list of actions to perform before the
%  image is saved.
  function AddAction(action)
    Actions{length(Actions)+1} = action;
  end

% Adds an 'undo-action' function to the list... these get processed after
%  the image has been saved, to restore the screen state.
  function AddUndoAction(action)
    UndoActions{length(UndoActions)+1} = action;
  end

% Remove leading and trailing edge white spaces
% from any string.
  function cropped_string = RemoveSpaces(string)
    if iscell(string)
      string = string{:};
    end
    I = regexp(string,'[^\s]');
    cropped_string = string(I(1):I(length(I)));
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
          'Unknown text horizontal alignment for "%s", defaulting to left',String);
        halign = 'l';
    end
    VAlign = get(handle,'VerticalAlignment');
    switch VAlign
      case {'base','bottom'}
        valign = 'b';
      case {'top','cap'}
        valign = 't';
      case {'middle'}
        valign = 'c';
      otherwise
        warning('matlabfrag:UnknownVertAlign',...
          'Unknown text vertical alignment for "%s", defaulting to bottom',String);
        valign = 'l';
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
    ht = findobj(handle,'type','text');
    ht = findobj(ht,'visible','on');
    ha = findobj(handle,'type','axes');
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
    % Open it up and extract the text
    try
      fh = fopen([tmp_file,'.eps'],'r');
      paintersfile = fread(fh,inf,'uint8=>char').';
      fh = fclose(fh);
    catch err
      if fh
        fh = close(fh);
      end
      rethrow(err);
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
    textData = sortrows(textData,1);
    % Open up the target file, and read the contents.
    try
      fh = fopen([filename,'.eps'],'r');
      epsfile = fread(fh,inf,'uint8=>char').';
      fh = fclose(fh);
    catch err
      if fh
        fh = close(fh);
      end
      rethrow(err);
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
    catch err
      if fh
        fh = fclose(fh);
      end
      rethrow(err);
    end
  end
    
end % of matlabfrag(FileName,p.Results.handle)