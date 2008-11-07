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
%                  | the number of points in the input vector. Default
%                  | is [0,0,0,0].
%
% EXAMPLE
% plot(1:10,rand(1,10));
% set(gca,'FontSize',8);
% title('badness $\phi$','interpreter','latex','fontweight','bold');
% xlabel('1 to 10','userdata','matlabfrag:\macro');
% ylabel('random','fontsize',14);
% matlabfrag('RandPlot','epspad',[5,0,0,0]);
%
% v0.4 1-Sep-2008
%
% Copyright 2007,2008 Zebb Prime
% Distributed under the GNU General Public License, see LICENSE.txt
% or the text appended to the source.
%
% Please report bugs to zebb.prime+matlabfrag@gmail.com
%
% Available from the Matlab File Exchange

function matlabfrag(FileName,varargin)

% Version information is taken from the above help information
HelpText = help('matlabfrag');
LatestVersion = regexp(HelpText,'(v[\d\.]+) ([\d]+\-[\w]+\-[\d]+)','tokens');
LatestVersion = LatestVersion{1};
Version = LatestVersion{1};
VersionDate = LatestVersion{2};
TEXHDR = sprintf('%% Generated using matlabfrag\n%% Version: %s\n%% Version Date: %s\n%% Author: Zebb Prime',...
  Version,VersionDate);

% Global macros
REPLACEMENT_FORMAT = '[%03d]';
REPLACEMENT_MAXLENGTH = 5;
USERDATA_PREFIX = 'matlabfrag:';

p = inputParser;
p.FunctionName = 'matlabfrag';

p.addRequired('FileName', @(x) ischar(x) );
p.addOptional('handle', gcf, @(x) ishandle(x) && strcmpi(get(x,'Type'),'figure') );
p.addOptional('epspad', [0,0,0,0], @(x) isnumeric(x) && (all(size(x) == [1 4])) );
p.parse(FileName,varargin{:});

Actions = {};
UndoActions = {};
StringCounter = 0;

% PsfragCmds are currently in the order:
% {LatexString, ReplacementString, Alignment, TextSize, Colour, 
%   FontAngle (1-italic,0-normal), FontWeight (1-bold,0-normal),
%   FixedWidth (1-true,0-false), LabelType }
PsfragCmds = {};

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
for ii=1:length(Actions)
  Actions{ii}();
end

% Export the image to an eps file
print('-depsc2','-loose',FileName);

% Pad the eps if requested
if any( p.Results.epspad )
  fh = fopen([FileName,'.eps'],'r');
  epsfile = fread(fh,inf,'uint8=>char').';
  fclose(fh);
  bb = regexpi(epsfile,'\%\%BoundingBox:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)','tokens');
  bb = str2double(bb{1});
  epsfile = regexprep(epsfile,sprintf('%i(\\s+)%i(\\s+)%i(\\s+)%i',bb),...
  sprintf('%i$1%i$2%i$3%i',bb+round(p.Results.epspad.*[-1,-1,1,1])));
  fh = fopen([FileName,'.eps'],'w');
  fwrite(fh,epsfile);
  fclose(fh);
end

% Apply the undo action to restore the image to how
%  was originally
for ii=1:length(UndoActions)
  UndoActions{ii}();
end

% Hide all of the hidden handles again
set(0,'showhiddenhandles',hidden);

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

try
  % Finally write the latex-file
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
  if ~isempty(regexpi(CurrentType,'tick'))
    TickType = 1;
  else
    TickType = 0;
  end
  fprintf(fid,'\n%%\n%%%% <%s>',CurrentType);
  for ii=1:size(PsfragCmds,1)
    % Test to see if the font size has changed
    if ~(CurrentFontSize == PsfragCmds{ii,4})
      CurrentFontSize = PsfragCmds{ii,4};
      NewFontStyle = 1;
    end
    % Test to see if the colour has changed
    if ~(CurrentColour == PsfragCmds{ii,5})
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
      if ~isempty(regexpi(CurrentType,'tick'))
        TickType = 1;
      end
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
      if TickType
        fprintf(fid,'[%s][%s]',PsfragCmds{ii,3},PsfragCmds{ii,3});
      else
        fprintf(fid,'[%s][bl]',PsfragCmds{ii,3});
      end
    end
    fprintf(fid,'{\\%s%s %s}%%',FontStylePrefix,...
      char(FontStyleId),RemoveSpaces(PsfragCmds{ii,1}));
  end
  fprintf(fid,'\n%%\n%%%% </%s>',CurrentType);

  fclose(fid);

catch
  if fid > 0
    fclose(fid);
  end
  err = lasterror;
  err.stack.line
  rethrow(lasterror);
end
% All done! Below are the sub-functions

  % Find all of the 'text' and 'axes' objects in the
  % figure and dispatch the processing of them
  function ProcessFigure(parent)
    % Dispatcher to different processing types
    axeshandles = findobj(parent,'Type','axes');
    texthandles = findobj(parent,'Type','text');
    for jj=1:length(axeshandles)
      ProcessTicks(axeshandles(jj));
    end
    for jj=1:length(texthandles)
      ProcessText(texthandles(jj));
    end
  end
 
  % Process a text handle, extracting the appropriate data
  %  and creating 'action' functions
  function ProcessText(handle)
    % Test to see if the string and userdata are empty or
    %  'visible' is set to off.
    String = get(handle,'string');
    UserData = get(handle,'UserData');
    UserString = {};
    if strcmpi(get(handle,'visible'),'off'); return; end;
    if isempty(sscanf(String,'%s')) 
      if ischar(UserData)
        if isempty(sscanf(UserData,'%s')); return; end
        UserString = regexp(UserData,[USERDATA_PREFIX,'(.*)'],'tokens');
      else return;
      end
    elseif ischar(UserData)
      if ~isempty(sscanf(UserData,'%s'))
        UserString = regexp(UserData,[USERDATA_PREFIX,'(.*)'],'tokens');
      end
    end
    % Retrieve the common options
    [FontSize,FontAngle,FontWeight,FixedWidth] = CommonOptions(handle);
    % Assign a replacement action for the string
    ReplacementString = ReplacementString();
    SetUnsetProperties(handle,'String',ReplacementString);
    % Check for a 'UserData' property, which replaces the string with latex
    if ~isempty(UserString)
      String = cell2mat(UserString{:});
    end
    % Replacement action for the interpreter
    if ~strcmpi(get(handle,'interpreter'),'none')
      SetUnsetProperties(handle,'interpreter','none');
    end
    % Make sure the final position is the same as the original one
    Pos = get(handle,'Position');
    AddAction( @() set(handle,'position',Pos) );
    % Process the strings alignment options
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
    % Now set the horizontal alignment to 'bl'
    SetUnsetProperties(handle,'VerticalAlignment','bottom','HorizontalAlignment','left');
    % Get the text colour
    Colour = get(handle,'color');
    % Finally create the replacement command
    AddPsfragCommand(String,ReplacementString,[valign,halign],...
      FontSize,Colour,FontAngle,FontWeight,FixedWidth,'text');
  end

  % Processes the 'ticks' of an axis, then returns.
  %  Don't do anything if it is a legend
  function ProcessTicks(handle)
    if strcmpi(get(handle,'tag'),'legend'); return; end;
    if strcmpi(get(handle,'visible'),'off'); return; end;
    [FontSize,FontAngle,FontWeight,FixedWidth] = CommonOptions(handle);
    for jj = ['x' 'y' 'z']
      AutoTick = strcmpi(get(handle,[jj,'tickmode']),'auto');
      AutoTickLabel = strcmpi(get(handle,[jj,'ticklabelmode']),'auto');
      ticklabels = get(handle,[jj,'ticklabel']);
      if ~isempty(ticklabels)
        tickcolour = get(handle,[jj,'color']);
        % Test to see if it is on a logarithmic scale
        if strcmpi(get(handle,[jj,'scale']),'log') && AutoTickLabel
          % And all of the values are integers
          ticklabelcell = mat2cell(ticklabels,ones(1,size(ticklabels,1)),size(ticklabels,2));
          if all(~isnan(str2double(ticklabelcell)))
          % If so, make the labels read 10^<TickLabel>
          ticklabels = strcat(ones(size(ticklabels,1),1)*'$10^{',ticklabels,...
            ones(size(ticklabels,1),1)*'}$');
          end
          % Test to see if there is a common factor
        elseif strcmpi(get(handle,[jj,'scale']),'linear') && AutoTick && AutoTickLabel
          ticks = get(handle,[jj,'tick']);
          for kk=1:size(ticklabels,1)
            % Find the first non-NaN ratio between tick labels and tick
            % values
            scale = ticks(kk)/str2double(ticklabels(kk,:));
            if ~isnan(scale); break; end;
          end
          % If the scale is not 1, then we need to place a marker near the
          % axis
          if scale ~= 1
            % Common required data...
            LatexScale = ['$\times10^{',num2str(log10(scale)),'}$'];
            XLims = get(handle,'xlim');
            YLims = get(handle,'ylim');
            LabelPos = get(get(handle,[jj,'label']),'Position');
            XAlignment = get(handle,'XAxisLocation');
            YAlignment = get(handle,'YAxisLocation');
            % For the x and y axes only
            if strcmpi(jj,'x')
              if strcmpi(XAlignment,'bottom'); Alignment = ['t',YAlignment(1)];
              else Alignment = ['b',YAlignment(1)]; end;
              if strcmpi(YAlignment,'left'); LabelPos(1) = XLims(2);
              else LabelPos(1) = XLims(1); end;
            elseif strcmpi(jj,'y')
              if strcmpi(YAlignment,'left'); Alignment = [XAlignment(1),'r'];
              else Alignment = [XAlignment(1),'l']; end;
              if strcmpi(XAlignment,'bottom'); LabelPos(2) = YLims(2);
              else LabelPos(2) = YLims(1); end;
            else
              Alignment = 'br';
              ZLims = get(handle,'zlim');
              LabelPos = [LabelPos(1),LabelPos(2),LabelPos(3)+ZLims(2)];
            end
            ReplacementText = ReplacementString();
            % Put a label in the right place
            hCA = get(p.Results.handle,'CurrentAxes');
            set(p.Results.handle,'CurrentAxes',handle);
            ht = text(LabelPos(1),LabelPos(2),LabelPos(3),ReplacementText,...
              'VerticalAlignment','bottom','HorizontalAlignment','left');
            set(p.Results.handle,'CurrentAxes',hCA);
            % Create the replacement command
            AddPsfragCommand(LatexScale,ReplacementText,Alignment,FontSize,...
              tickcolour,FontAngle,FontWeight,FixedWidth,[jj,'scale']);
            % Delete the label
            AddUndoAction( @() delete(ht) );
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
            ticklabels = strcat(ones(size(ticklabels,1),1)*'$',ticklabels,...
              ones(size(ticklabels,1),1)*'$');
          end
          clear TicksAreNumbers
          tickreplacements = char(zeros(size(ticklabels,1),REPLACEMENT_MAXLENGTH));
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
          tickreplacements(kk,:) = sprintf(['% ',...
            num2str(REPLACEMENT_MAXLENGTH),'s'],ReplacementString());
          AddPsfragCommand(ticklabels(kk,:),tickreplacements(kk,:),...
            tickalignment,FontSize,tickcolour,FontAngle,FontWeight,...
            FixedWidth,[jj,'tick']);
        end
        % Now add the replacement action...
          SetUnsetProperties(handle,[jj,'ticklabel'],char(tickreplacements));
          if AutoTick; AddUndoAction( @() set(handle,[jj,'tickmode'],'auto') ); end;
          if AutoTickLabel; AddUndoAction( @() set(handle,[jj,'ticklabelmode'],'auto')); end;
      end
    end
  end

  % Get the next replacement string
  function ReplacementString = ReplacementString()
    ReplacementString = sprintf(REPLACEMENT_FORMAT,StringCounter);
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
    if FontAngle
      SetUnsetProperties(handle,'FontAngle','normal');
    end
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
    if FontWeight
      SetUnsetProperties(handle,'FontWeight','normal');
    end
    % Test to see if the font is 'fixed width'
    if strcmpi(get(handle,'FontName'),'FixedWidth')
      FixedWidth = 1;
    else
      FixedWidth = 0;
    end
    if FixedWidth
      SetUnsetProperties(handle,'FontName','Helvetica');
    end
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

end % of matlabfrag(FileName,p.Results.handle)

% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
% 
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% 
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <http://www.gnu.org/licenses/>.