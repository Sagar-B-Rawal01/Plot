classdef TelemetryWorkbench < handle
    % TELEMETRYWORKBENCH - Modular, OOP Telemetry Analyzer
    % Architecture: MVC (Model-View-Controller)
    
    %% ====================================================================
    %% 1. STATE (MODEL)
    %% ====================================================================
    properties (Access = public)
        % Core Data
        DataVars struct      % Master dictionary of processed signals
        Plots cell           % Array of plot configurations
        Events cell          % Array of event logic configurations
        LoadedFile char      % Name of the active MAT file
        
        % Interaction States
        SelectedRows double  % Indices of selected rows in the data manager
        EvalStack cell       % Tracks derived math to prevent infinite loops
        ExtState struct      % State memory for the extraction tool
    end
    
    %% ====================================================================
    %% 2. UI HANDLES (VIEW)
    %% ====================================================================
    properties (Access = public)
        UI struct            % Master registry for all graphical components
    end
    
        %% ====================================================================
    %% 3. INITIALIZATION
    %% ====================================================================
    methods
        function obj = TelemetryWorkbench()
            % 1. Initialize State
            obj.DataVars = struct();
            obj.Plots = {};
            obj.Events = {};
            obj.LoadedFile = 'None';
            obj.SelectedRows = [];
            obj.EvalStack = {};
            obj.ExtState = struct('startX', NaN, 'endX', NaN, 'startIdx', NaN, 'endIdx', NaN, 'hStart', [], 'hEnd', []);
            
            % 2. Initialize UI Struct (CRITICAL FIX)
            obj.UI = struct();
            
            % 3. Build the UI
            obj.buildApplicationUI();
            
            % 4. Log startup
            obj.logMessage('SYSTEM', 'Modular Telemetry Workbench initialized. Ready for data.');
        end
    end

    %% ====================================================================
    %% 4. USER INTERFACE BUILDERS (VIEW)
    %% ====================================================================
    methods (Access = private)
        
        function buildApplicationUI(obj)
            obj.UI.Fig = uifigure('Name', 'Telemetry Workbench', 'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);
            
            % Master Grid Layout
            mGrid = uigridlayout(obj.UI.Fig, [2 1]);
            mGrid.RowHeight = {'1x', 120};
            
            % Tab Group
            tg = uitabgroup(mGrid);
            tData    = uitab(tg, 'Title', '1. Data Manager');
            tPlot    = uitab(tg, 'Title', '2. Plot Builder');
            tEvent   = uitab(tg, 'Title', '3. Event Engine');
            tExtract = uitab(tg, 'Title', '4. Segment Extraction');
            
            % System Console
            obj.UI.Console = uitextarea(mGrid, 'Editable', 'off', 'FontName', 'Consolas', ...
                'BackgroundColor', [0.1 0.1 0.1], 'FontColor', [0.2 0.9 0.2]);
            
            % Construct Tabs
            obj.buildDataTab(tData);
            obj.buildPlotTab(tPlot);
            obj.buildEventTab(tEvent);
            obj.buildExtractTab(tExtract);
        end
        
        function buildDataTab(obj, tab)
            g = uigridlayout(tab, [3 1]); g.RowHeight = {50, 110, '1x'};
            
            % Top Bar
            r1 = uigridlayout(g, [1 4]); r1.Padding = [0 0 0 0];
            uibutton(r1, 'Text', 'Load MAT File', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@obj.actionLoadMat, 'Loading data...'));
            obj.UI.txtSearch = uieditfield(r1, 'text', 'Placeholder', 'Filter channels...', 'ValueChangedFcn', @(~,~)obj.safeExecute(@obj.actionRefreshTable, ''));
            uibutton(r1, 'Text', '💾 Save State', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@obj.actionSaveState, 'Saving state...'));
            uibutton(r1, 'Text', '📂 Load State', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@obj.actionLoadState, 'Loading state...'));
            
            % Derived Signals
            pnlDeriv = uipanel(g, 'Title', 'Derived Signal Engine');
            gd = uigridlayout(pnlDeriv, [2 4]); gd.RowHeight = {25, 25};
            uilabel(gd, 'Text', 'Name:'); obj.UI.derName = uieditfield(gd, 'Value', 'speed');
            uilabel(gd, 'Text', 'Math:'); obj.UI.derExpr = uieditfield(gd, 'Value', 'sim.vx * 2');
            uilabel(gd, 'Text', 'Unit:'); obj.UI.derUnit = uieditfield(gd, 'Value', 'm/s');
            btnDeriv = uibutton(gd, 'Text', 'Create Derived Signal', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@obj.actionCreateDerived, 'Creating signal...'));
            btnDeriv.Layout.Row = 2; btnDeriv.Layout.Column = 4;
            
            % Table
            pnlTab = uipanel(g, 'Title', 'Signal Metadata');
            gt = uigridlayout(pnlTab, [2 1]); gt.RowHeight = {30, '1x'};
            
            rt = uigridlayout(gt, [1 4]); rt.Padding = [0 0 0 0];
            uibutton(rt, 'Text', 'Apply Scale', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@()obj.actionApplyModifier('scale'), 'Scaling...'));
            uibutton(rt, 'Text', 'Apply Offset', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@()obj.actionApplyModifier('offset'), 'Offsetting...'));
            uibutton(rt, 'Text', 'Apply Prefix', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@obj.actionApplyPrefix, 'Prefixing...'));
            uibutton(rt, 'Text', 'Reset Modifiers', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@obj.actionResetModifiers, 'Resetting...'));
            
headers = {'Key', 'Label', 'Unit', 'Size', 'Scale', 'Offset', 'Transpose', 'Style', 'Width', 'Color', 'IsDerived'};
            obj.UI.dataTable = uitable(gt, 'ColumnName', headers, 'CellSelectionCallback', @(~,ev)obj.actionTableSelect(ev), 'CellEditCallback', @(~,ev)obj.safeExecute(@()obj.actionTableEdit(ev), ''));
            obj.UI.dataTable.ColumnEditable = [false false false true true true true true true true false];
        end
        
        function buildPlotTab(obj, tab)
            g = uigridlayout(tab, [2 3]); g.ColumnWidth = {300, 300, '1x'}; g.RowHeight = {'1x', 140};
            
            % Left - Signal Selection
            pnlSig = uipanel(g, 'Title', 'Signal Selection');
            gs = uigridlayout(pnlSig, [4 2]); gs.RowHeight = {25, 25, '1x', '1x'};
            uilabel(gs, 'Text', 'X-Search:'); obj.UI.pltXSearch = uieditfield(gs, 'ValueChangedFcn', @(~,~)obj.safeExecute(@()obj.actionFilterList('x'), ''));
            uilabel(gs, 'Text', 'Y-Search:'); obj.UI.pltYSearch = uieditfield(gs, 'ValueChangedFcn', @(~,~)obj.safeExecute(@()obj.actionFilterList('y'), ''));
            uilabel(gs, 'Text', 'X Signal:'); obj.UI.pltXList = uilistbox(gs);
            uilabel(gs, 'Text', 'Y Signals:'); obj.UI.pltYList = uilistbox(gs, 'Multiselect', 'on');
            
            % Center - Style
            pnlSty = uipanel(g, 'Title', 'Subplot Settings');
            gst = uigridlayout(pnlSty, [7 2]); gst.RowHeight = num2cell(repmat(25, 1, 7));
            uilabel(gst, 'Text', 'Fig #:'); obj.UI.pltFig = uispinner(gst, 'Value', 1, 'LowerLimit', 1);
            uilabel(gst, 'Text', 'Rows:'); obj.UI.pltRow = uispinner(gst, 'Value', 1, 'LowerLimit', 1);
            uilabel(gst, 'Text', 'Cols:'); obj.UI.pltCol = uispinner(gst, 'Value', 1, 'LowerLimit', 1);
            uilabel(gst, 'Text', 'Pos:');  obj.UI.pltPos = uispinner(gst, 'Value', 1, 'LowerLimit', 1);
            uilabel(gst, 'Text', 'Style:'); obj.UI.pltType = uidropdown(gst, 'Items', {'plot', 'scatter', 'stairs'});
            obj.UI.pltGrid = uicheckbox(gst, 'Text', 'Grid', 'Value', true);
            obj.UI.pltLeg  = uicheckbox(gst, 'Text', 'Legend', 'Value', true);
            
            % Right - Manifest
            pnlMan = uipanel(g, 'Title', 'Plot Manifest'); pnlMan.Layout.Column = 3;
            gm = uigridlayout(pnlMan, [5 1]); gm.RowHeight = {'1x', 30, 30, 30, 30};
            obj.UI.plotManifest = uilistbox(gm);
            uibutton(gm, 'Text', 'Add Standard Plot', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@()obj.actionAddPlot(false), 'Plot added.'));
            uibutton(gm, 'Text', 'Delete Selected', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@obj.actionDeleteManifestItem, 'Item deleted.'));
            uibutton(gm, 'Text', '► RENDER PREVIEW', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@obj.renderAll, 'Rendering...'), 'BackgroundColor', [0.7 0.9 0.7]);
            uibutton(gm, 'Text', 'Generate M-File Script', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@obj.actionExportScript, 'Generating script...'), 'BackgroundColor', [1 0.9 0.6]);
            
            % Bottom - Custom Plot
            pnlCus = uipanel(g, 'Title', 'Custom Math Plot'); pnlCus.Layout.Row = 2; pnlCus.Layout.Column = [1 3];
            gc = uigridlayout(pnlCus, [2 4]); gc.RowHeight = {25, 30};
            uilabel(gc, 'Text', 'Custom X:'); obj.UI.cusX = uieditfield(gc, 'Value', 'sim.t');
            uilabel(gc, 'Text', 'Custom Y:'); obj.UI.cusY = uieditfield(gc, 'Value', 'sim.speed');
            uilabel(gc, 'Text', 'Label:'); obj.UI.cusLbl = uieditfield(gc, 'Value', 'Math Trace');
            btnC = uibutton(gc, 'Text', 'Add Custom Plot', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@()obj.actionAddPlot(true), 'Custom plot added.'));
            btnC.Layout.Row = 2; btnC.Layout.Column = 4;
        end
        
        function buildEventTab(obj, tab)
            g = uigridlayout(tab, [1 2]);
            p = uipanel(g, 'Title', 'Threshold Logic Engine');
            eg = uigridlayout(p, [6 2]); eg.RowHeight = repmat({25}, 1, 6);
            uilabel(eg, 'Text', 'Event Name:'); obj.UI.evName = uieditfield(eg, 'Value', 'Warning');
            uilabel(eg, 'Text', 'Logic (e.g. speed > 9):'); obj.UI.evLogic = uieditfield(eg, 'Value', '');
            uilabel(eg, 'Text', 'Target Fig #:'); obj.UI.evFig = uispinner(eg, 'Value', 1);
            uilabel(eg, 'Text', 'Color:'); obj.UI.evColor = uidropdown(eg, 'Items', {'r','g','b','y','m','c','k'});
            uilabel(eg, 'Text', 'Opacity (0-1):'); obj.UI.evOpac = uispinner(eg, 'Value', 0.2, 'Step', 0.1);
            uibutton(eg, 'Text', 'Process Event Logic', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@obj.actionAddEvent, 'Processing event...'), 'BackgroundColor', [0.8 1 0.8]);
        end
        
        function buildExtractTab(obj, tab)
            g = uigridlayout(tab, [1 3]); g.ColumnWidth = {300, '1x', 300};
            
            pl = uipanel(g, 'Title', 'Reference Setup');
            gl = uigridlayout(pl, [3 1]); gl.RowHeight = {25, '1x', '1x'};
            uibutton(gl, 'Text', 'Render Reference Plot', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@obj.actionRenderExtract, 'Rendering reference...'));
            obj.UI.extX = uilistbox(gl); obj.UI.extY = uilistbox(gl);
            
            pc = uipanel(g, 'Title', 'Interactive Trimming');
            gc = uigridlayout(pc, [1 1]);
            obj.UI.extAxes = uiaxes(gc);
            
            pr = uipanel(g, 'Title', 'Export Dashboard');
            gr = uigridlayout(pr, [6 1]); gr.RowHeight = {30, 25, 25, '1x', 25, 30};
            uibutton(gr, 'Text', '📍 Enable Manual Click Select', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@obj.actionEnableExtCursor, ''));
            obj.UI.lblExtStart = uilabel(gr, 'Text', 'Start: NaN');
            obj.UI.lblExtEnd = uilabel(gr, 'Text', 'End: NaN');
            obj.UI.extExportList = uilistbox(gr, 'Multiselect', 'on');
            obj.UI.extFile = uieditfield(gr, 'Value', 'export.csv');
            uibutton(gr, 'Text', '🚀 Export Data', 'ButtonPushedFcn', @(~,~)obj.safeExecute(@obj.actionExportData, 'Exporting...'), 'BackgroundColor', [0.7 0.9 0.7]);
        end
    end
    
    %% ====================================================================
    %% 5. ERROR HANDLING & LOGGING (DEBUGGABILITY)
    %% ====================================================================
    methods (Access = private)
        
        function safeExecute(obj, functionHandle, startMsg)
            % The core wrapper that prevents silent failures and prints debug info
            try
                if ~isempty(startMsg)
                    obj.logMessage('ACTION', startMsg);
                end
                functionHandle();
            catch ME
                % Extract exactly where it failed for easy debugging
                errLine = ME.stack(1).line;
                errFile = ME.stack(1).name;
                errMsg = sprintf('%s (Line %d in %s)', ME.message, errLine, errFile);
                
                % Print to UI Console
                obj.logMessage('ERROR', errMsg);
                % Print to MATLAB Command Window (Red text)
                fprintf(2, '[DEBUG ERROR] %s\n', errMsg); 
                
                uialert(obj.UI.Fig, errMsg, 'Runtime Error');
            end
        end
        
        function logMessage(obj, level, msg)
            txt = sprintf('[%s] [%s] %s', datestr(now, 'HH:MM:SS'), level, msg);
            obj.UI.Console.Value{end+1} = txt;
            scroll(obj.UI.Console, 'bottom');
        end
    end
    
    %% ====================================================================
    %% 6. CONTROLLER ACTIONS (LOGIC)
    %% ====================================================================
    methods (Access = private)
        
        % --- File Management ---
        function actionLoadMat(obj)
            [file, path] = uigetfile('*.mat', 'Select Telemetry Data');
            if file == 0, return; end
            obj.LoadedFile = file;
            rawStruct = load(fullfile(path, file));
            
            obj.DataVars = struct(); % clear old
            obj.parseStructRecursive(rawStruct, '');
            obj.actionRefreshTable();
            obj.syncUILists();
        end
        
        function parseStructRecursive(obj, inStruct, prefix)
            fn = fieldnames(inStruct);
            for i = 1:length(fn)
                val = inStruct.(fn{i});
                fName = fn{i};
                if isempty(prefix), fullPath = fName; else, fullPath = [prefix '.' fName]; end
                
                if isstruct(val)
                    obj.parseStructRecursive(val, fullPath);
                else
                    safeName = matlab.lang.makeValidName(fullPath);
                    tokens = split(fullPath, '.'); label = tokens{end};
                    obj.DataVars.(safeName) = struct('data', val, 'sourcePath', fullPath, 'label', label, ...
                        'unit', '', 'scale', 1, 'offset', 0, 'transpose', false, ...
                        'style', '-', 'width', 1.5, 'color', 'auto', 'isDerived', false, ...
                        'expr', '', 'cache', []);
                end
            end
        end
        
        % --- Math / Signal Processing Engine ---
        function sig = fetchSignal(obj, key)
            meta = obj.DataVars.(key);
            
            % Protection against Infinite Recursion Loops
            if meta.isDerived

                if ismember(key, obj.EvalStack)
                    chain = strjoin(obj.EvalStack, ' -> ');
                    error('Cyclic dependency detected: %s -> %s', chain, key);
                end

                obj.EvalStack{end+1} = key;

                try
                    sig = obj.evaluateMathSafely(meta.expr);

                    % Remove only last pushed item
                    sig = obj.evaluateMathSafely(meta.expr);

                    obj.DataVars.(key).cache = sig;

                    obj.EvalStack(end) = [];

                catch ME
                    obj.EvalStack = {};
                    rethrow(ME);
                end

                return;
            end

            % Cache hit
            if ~isempty(meta.cache), sig = meta.cache; return; end

            % Format raw data
            raw = meta.data;
            if istable(raw), raw = table2array(raw); end
            if isrow(raw), raw = raw(:); end
            if meta.transpose, raw = raw'; end
            raw = double(raw);

            if size(raw, 2) > 1, raw = raw(:,1); end
            
            sig = raw * meta.scale + meta.offset;
            sig(~isfinite(sig)) = NaN;
            
            % Update Cache
            obj.DataVars.(key).cache = sig; 
        end
       


        function out = evaluateMathSafely(obj, expr)
    fn = fieldnames(obj.DataVars);

    % ---------------------------------------------------------
    % Inject all signals into local workspace safely
    % ---------------------------------------------------------
    for i = 1:length(fn)
        meta = obj.DataVars.(fn{i});

        % IMPORTANT:
        % Do NOT recursively evaluate derived signals here
        % unless needed.

        if meta.isDerived
            % Skip self-reference protection
            if ismember(fn{i}, obj.EvalStack)
                continue;
            end

            try
                val = obj.fetchSignal(fn{i});
            catch
                continue;
            end
        else
            % RAW SIGNAL PATH
            raw = meta.data;

            if istable(raw)
                raw = table2array(raw);
            end

            if isrow(raw)
                raw = raw(:);
            end

            if meta.transpose
                raw = raw';
            end

            raw = double(raw);

            if size(raw,2) > 1
                raw = raw(:,1);
            end

            val = raw * meta.scale + meta.offset;
            val(~isfinite(val)) = NaN;
        end

        % Create variable hierarchy
        try
            eval([meta.sourcePath ' = val;']);
        catch
            % Ignore invalid variable nesting
        end
    end

    % ---------------------------------------------------------
    % Evaluate user expression
    % ---------------------------------------------------------
    out = eval(expr);
end


        function actionCreateDerived(obj)
            name = strtrim(obj.UI.derName.Value);
            expr = strtrim(obj.UI.derExpr.Value);
            if isempty(name) || isempty(expr), error('Name and Expression required.'); end
            
            safeName = matlab.lang.makeValidName(name);
            out = obj.evaluateMathSafely(expr);
            
            if ~isnumeric(out), error('Expression must result in a numeric array.'); end
            
            obj.DataVars.(safeName) = struct('data', out(:), 'sourcePath', safeName, 'label', name, ...
                'unit', obj.UI.derUnit.Value, 'scale', 1, 'offset', 0, 'transpose', false, ...
                'style', '-', 'width', 1.5, 'color', 'auto', 'isDerived', true, ...
                'expr', expr, 'cache', out(:));
            
            obj.actionRefreshTable();
            obj.syncUILists();
        end
        
        % --- UI State Synchronization ---
        function actionRefreshTable(obj)
            k = lower(obj.UI.txtSearch.Value);
            fn = fieldnames(obj.DataVars);
            
            d = cell(0, 11); rowIdx = 1;
            for i = 1:length(fn)
                v = obj.DataVars.(fn{i});
                % Search Key or Label
                if isempty(k) || contains(lower(v.label), k) || contains(lower(fn{i}), k)
                    raw = v.data;



raw = v.data;

try
    sz = size(raw);

    % Show transposed interpretation
    if v.transpose
        sz = fliplr(sz);
    end

    szTxt = sprintf('%dx%d', sz(1), sz(2));
catch
    szTxt = 'Unknown';
end

d(rowIdx, :) = {
    fn{i}, ...
    v.label, ...
    v.unit, ...
    szTxt, ...
    v.scale, ...
    v.offset, ...
    v.transpose, ...
    v.style, ...
    v.width, ...
    v.color, ...
    v.isDerived ...
};
                    rowIdx = rowIdx + 1;
                end
            end
            obj.UI.dataTable.Data = d;
        end
        
        function syncUILists(obj)
            fn = fieldnames(obj.DataVars);
            lbls = cell(size(fn));
            for i=1:length(fn), lbls{i} = obj.DataVars.(fn{i}).label; end
            
            obj.UI.pltXList.Items = lbls; obj.UI.pltXList.ItemsData = fn;
            obj.UI.pltYList.Items = lbls; obj.UI.pltYList.ItemsData = fn;
            obj.UI.extX.Items = lbls; obj.UI.extX.ItemsData = fn;
            obj.UI.extY.Items = lbls; obj.UI.extY.ItemsData = fn;
            obj.UI.extExportList.Items = lbls; obj.UI.extExportList.ItemsData = fn;
        end
        
        function actionFilterList(obj, axis)
            if strcmp(axis, 'x')
                txt = lower(obj.UI.pltXSearch.Value); list = obj.UI.pltXList;
            else
                txt = lower(obj.UI.pltYSearch.Value); list = obj.UI.pltYList;
            end
            
            fn = fieldnames(obj.DataVars);
            matches = {}; lbls = {};
            for i = 1:length(fn)
                lbl = obj.DataVars.(fn{i}).label;
                if isempty(txt) || contains(lower(lbl), txt) || contains(lower(fn{i}), txt)
                    matches{end+1} = fn{i}; lbls{end+1} = lbl; %#ok<AGROW>
                end
            end
            list.Items = lbls; list.ItemsData = matches;
        end
        
        function syncManifest(obj)
            items = {}; ids = {};
            for i = 1:length(obj.Plots)
                p = obj.Plots{i};
                if p.isCus, txt = sprintf('[Plot] F%d(S%d) %s', p.f, p.p, p.name);
                else, txt = sprintf('[Plot] F%d(S%d) %s', p.f, p.p, strjoin(p.y, ',')); end
                items{end+1} = txt; ids{end+1} = p.id; %#ok<AGROW>
            end
            for i = 1:length(obj.Events)
                e = obj.Events{i};
                items{end+1} = sprintf('[Event] F%d %s', e.fig, e.name); ids{end+1} = e.id; %#ok<AGROW>
            end
            obj.UI.plotManifest.Items = items;
            obj.UI.plotManifest.ItemsData = ids;
            obj.UI.plotManifest.Value = {}; % Clear selection
        end
        
        % --- Table Interaction ---
        function actionTableSelect(obj, ev)
            if isempty(ev.Indices), obj.SelectedRows = []; return; end
            obj.SelectedRows = unique(ev.Indices(:,1))';
        end
        
        function actionTableEdit(obj, ev)
            r = ev.Indices(1); c = ev.Indices(2);
            key = obj.UI.dataTable.Data{r, 1}; val = ev.NewData;
            switch c
    case 2
        obj.DataVars.(key).label = val;

    case 3
        obj.DataVars.(key).unit = val;

    case 5
        obj.DataVars.(key).scale = val;
        obj.DataVars.(key).cache = [];

    case 6
        obj.DataVars.(key).offset = val;
        obj.DataVars.(key).cache = [];

    case 7
        obj.DataVars.(key).transpose = val;
        obj.DataVars.(key).cache = [];

    case 8
        obj.DataVars.(key).style = val;

    case 9
        obj.DataVars.(key).width = val;

    case 10
        obj.DataVars.(key).color = val;
end
            obj.renderAll();
        end
        
        function keys = getSelectedKeys(obj)
            keys = {};
            if isempty(obj.SelectedRows), return; end
            for i = 1:length(obj.SelectedRows)
                r = obj.SelectedRows(i);
                if r <= size(obj.UI.dataTable.Data, 1)
                    keys{end+1} = obj.UI.dataTable.Data{r, 1}; %#ok<AGROW>
                end
            end
        end
        
        function actionApplyModifier(obj, mode)
            keys = obj.getSelectedKeys();
            if isempty(keys), error('Select rows in the table first.'); end
            val = inputdlg(['Enter numerical ' mode ':']);
            if isempty(val), return; end
            num = str2double(val{1});
            if isnan(num), error('Invalid number.'); end
            
            for i = 1:length(keys)
                obj.DataVars.(keys{i}).(mode) = num;
                obj.DataVars.(keys{i}).cache = [];
            end
            obj.actionRefreshTable(); obj.renderAll();
        end
        
        function actionApplyPrefix(obj)
            keys = obj.getSelectedKeys();
            if isempty(keys), error('Select rows in the table first.'); end
            val = inputdlg('Enter Prefix:');
            if isempty(val), return; end
            for i = 1:length(keys)
                obj.DataVars.(keys{i}).label = [val{1} obj.DataVars.(keys{i}).label];
            end
            obj.actionRefreshTable(); obj.syncUILists();
        end
        
        function actionResetModifiers(obj)
            keys = obj.getSelectedKeys();
            if isempty(keys), keys = fieldnames(obj.DataVars); end % Do all if none selected
            for i = 1:length(keys)
                obj.DataVars.(keys{i}).scale = 1;
                obj.DataVars.(keys{i}).offset = 0;
                obj.DataVars.(keys{i}).cache = [];
            end
            obj.actionRefreshTable(); obj.renderAll();
        end
        
        % --- Manifest Operations ---
        function actionAddPlot(obj, isCustom)
            id = char(matlab.lang.internal.uuid);
            r = obj.UI.pltRow.Value; c = obj.UI.pltCol.Value; pNum = obj.UI.pltPos.Value;
            if pNum > (r * c), error('Subplot position exceeds Matrix size (Rows x Cols).'); end

            if isCustom
                p = struct('id', id, 'isCus', true, 'xExp', obj.UI.cusX.Value, 'yExp', obj.UI.cusY.Value, ...
                    'name', obj.UI.cusLbl.Value, 'f', obj.UI.pltFig.Value, 'r', r, 'c', c, 'p', pNum, ...
                    'type', obj.UI.pltType.Value, 'grid', obj.UI.pltGrid.Value, 'leg', obj.UI.pltLeg.Value);
            else
                if isempty(obj.UI.pltXList.Value) || isempty(obj.UI.pltYList.Value), error('Select X and Y signals.'); end
                p = struct('id', id, 'isCus', false, 'x', obj.UI.pltXList.Value, 'y', {obj.UI.pltYList.Value}, ...
                    'f', obj.UI.pltFig.Value, 'r', r, 'c', c, 'p', pNum, ...
                    'type', obj.UI.pltType.Value, 'grid', obj.UI.pltGrid.Value, 'leg', obj.UI.pltLeg.Value);
            end
            obj.Plots{end+1} = p;
            obj.syncManifest(); obj.renderAll();
        end

        
        function actionDeleteManifestItem(obj)
            selId = obj.UI.plotManifest.Value;
            if isempty(selId), return; end

            obj.Plots = obj.Plots(~cellfun(@(x) strcmp(x.id, selId), obj.Plots));
            obj.Events = obj.Events(~cellfun(@(x) strcmp(x.id, selId), obj.Events));

            obj.syncManifest(); obj.renderAll();
        end

function actionAddEvent(obj)

    % =========================================================
    % Validate expression
    % =========================================================
    expr = strtrim(obj.UI.evLogic.Value);

    if isempty(expr)
        error('Event logic cannot be empty.');
    end

    % =========================================================
    % Evaluate event mask
    % =========================================================
    mask = obj.evaluateMathSafely(expr);

    if isempty(mask)
        error('Event expression returned empty.');
    end

    mask = double(mask(:));

    mask(~isfinite(mask)) = 0;

    mask(mask ~= 0) = 1;

    % =========================================================
    % Detect transitions using diff
    %
    % +1 => ON
    % -1 => OFF
    % =========================================================
    d = diff([0; mask; 0]);

    startIdx = find(d == 1);

    stopIdx = find(d == -1);

    stopIdx(stopIdx > length(mask)) = length(mask);

    if isempty(startIdx)
        error('No event transitions detected.');
    end

    % =========================================================
    % Ask user for X-axis signal
    % =========================================================
    fn = fieldnames(obj.DataVars);

    labels = cell(size(fn));

    for i = 1:length(fn)
        labels{i} = obj.DataVars.(fn{i}).label;
    end

    [indx, tf] = listdlg( ...
        'PromptString', 'Select X-axis signal for event timeline', ...
        'SelectionMode', 'single', ...
        'ListString', labels);

    if ~tf
        return;
    end

    xKey = fn{indx};

    % =========================================================
    % Fetch X-axis signal
    % =========================================================
    t = obj.fetchSignal(xKey);

    t = t(:);

    if length(t) < length(mask)
        error('X-axis signal shorter than event mask.');
    end

    t = t(1:length(mask));

    % =========================================================
    % Store event structure
    % =========================================================
    e = struct();

    e.id    = char(matlab.lang.internal.uuid);

    e.name  = obj.UI.evName.Value;

    e.logic = expr;

    e.onT   = t(startIdx);

    e.offT  = t(stopIdx);

    e.fig   = obj.UI.evFig.Value;

    e.c     = obj.UI.evColor.Value;

    e.alpha = obj.UI.evOpac.Value;

    obj.Events{end+1} = e;

    % =========================================================
    % Logging
    % =========================================================
    obj.logMessage( ...
        'EVENT', ...
        sprintf('%s -> %d ON transitions detected.', ...
        e.name, length(startIdx)));

    % =========================================================
    % Draw directly on plot
    % =========================================================
    fig = figure(e.fig);

    axList = findall(fig, ...
        'Type', 'axes', ...
        '-not', 'Tag', 'legend');

    for a = 1:length(axList)

        ax = axList(a);

        hold(ax, 'on');

        yl = ylim(ax);

        for k = 1:length(e.onT)

            % -----------------------------
            % ON LINE
            % -----------------------------
            xline(ax, ...
                e.onT(k), ...
                '-', ...
                ['ON : ' e.name], ...
                'Color', 'g', ...
                'LineWidth', 1.5, ...
                'LabelVerticalAlignment', 'middle', ...
                'LabelOrientation', 'horizontal');

            % -----------------------------
            % OFF LINE
            % -----------------------------
            xline(ax, ...
                e.offT(k), ...
                '-', ...
                ['OFF : ' e.name], ...
                'Color', 'r', ...
                'LineWidth', 1.5, ...
                'LabelVerticalAlignment', 'middle', ...
                'LabelOrientation', 'horizontal');

            % -----------------------------
            % Optional shaded region
            % -----------------------------
            patch(ax, ...
                [e.onT(k) e.offT(k) e.offT(k) e.onT(k)], ...
                [yl(1) yl(1) yl(2) yl(2)], ...
                e.c, ...
                'FaceAlpha', e.alpha, ...
                'EdgeColor', 'none', ...
                'HandleVisibility', 'off');

        end
    end

    obj.syncManifest();

end
        
        % --- Core Rendering Engine ---
        function renderAll(obj)
            % 1. Get required figures and clear them
            allFigs = unique([cellfun(@(x) x.f, obj.Plots), cellfun(@(x) x.fig, obj.Events)]);
            for i = 1:length(allFigs)
                fHandle = figure(allFigs(i)); clf(fHandle);
            end
            
            % 2. Render Plots
            for i = 1:length(obj.Plots)
                p = obj.Plots{i};
                ax = subplot(p.r, p.c, p.p, 'Parent', figure(p.f)); hold(ax, 'on');
                
                if p.isCus
                    xV = obj.evaluateMathSafely(p.xExp); yV = obj.evaluateMathSafely(p.yExp);
                    plot(ax, xV, yV, 'LineWidth', 1.5, 'DisplayName', p.name);
                    xlabel(ax, p.xExp, 'Interpreter', 'none'); ylabel(ax, p.yExp, 'Interpreter', 'none');
                else
                    xV = obj.fetchSignal(p.x); lbls = {};
                    for j = 1:length(p.y)
                        yV = obj.fetchSignal(p.y{j});
                        meta = obj.DataVars.(p.y{j});
                        len = min(length(xV), length(yV));
                        
                        args = {'LineWidth', meta.width, 'LineStyle', meta.style, 'DisplayName', meta.label};
                        if ~strcmp(meta.color, 'auto'), args = [args, 'Color', meta.color]; end
                        feval(p.type, ax, xV(1:len), yV(1:len), args{:});
                        lbls{end+1} = meta.label; %#ok<AGROW>
                    end
                    xlabel(ax, obj.DataVars.(p.x).label, 'Interpreter', 'none');
                    if length(lbls) <= 2, ylabel(ax, strjoin(lbls, ' / '), 'Interpreter', 'none');
                    else, ylabel(ax, sprintf('[%d Signals]', length(lbls)), 'Interpreter', 'none'); end
                end
                if p.grid, grid(ax, 'on'); end
                if p.leg, legend(ax, 'show', 'Interpreter', 'none'); end
            end
            
            % 3. Render Events
            for i = 1:length(obj.Events)
                e = obj.Events{i};
                axesList = findall(figure(e.fig), 'Type', 'axes', '-not', 'Tag', 'legend', '-not', 'Tag', 'Colorbar');
                for a = 1:length(axesList)
                    ax = axesList(a);
                    delete(findobj(ax, 'Tag', 'eventOverlay')); % Prevent layering memory leaks
                    yl = ylim(ax); hold(ax, 'on');
                    for t = 1:length(e.onT)
                        patch(ax, [e.onT(t) e.offT(t) e.offT(t) e.onT(t)], [yl(1) yl(1) yl(2) yl(2)], e.c, 'FaceAlpha', e.alpha, 'EdgeColor', 'none', 'Tag', 'eventOverlay', 'HandleVisibility', 'off');
                    end
                end
            end
        end
        
        % --- Script Export ---
        function actionExportScript(obj)
            [file, path] = uiputfile('*.m', 'Save Script', 'plot_telemetry.m');
            if file == 0, return; end
            fid = fopen(fullfile(path, file), 'w');
            
            fprintf(fid, '%% Standalone Telemetry Script\nclearvars; clc;\n');
            fprintf(fid, 'load(''%s'');\n\n', obj.LoadedFile);
            
            % Raw to formatted
            fn = fieldnames(obj.DataVars);
            

            for i = 1:length(fn)

    m = obj.DataVars.(fn{i});

    if ~m.isDerived

        fprintf(fid, ...
            ['%s = double(%s);\n' ...
             'if %d\n' ...
             '    %s = %s'';\n' ...
             'end\n' ...
             'if isrow(%s)\n' ...
             '    %s = %s(:);\n' ...
             'end\n' ...
             'if size(%s,2) > 1\n' ...
             '    %s = %s(:,1);\n' ...
             'end\n' ...
             '%s = %s * %g + %g;\n\n'], ...
             m.sourcePath, ...
             m.sourcePath, ...
             m.transpose, ...
             m.sourcePath, m.sourcePath, ...
             m.sourcePath, ...
             m.sourcePath, m.sourcePath, ...
             m.sourcePath, ...
             m.sourcePath, m.sourcePath, ...
             m.sourcePath, m.sourcePath, ...
             m.scale, m.offset);

    end
end
            
            % Derived
            for i = 1:length(fn)
                m = obj.DataVars.(fn{i});
                if m.isDerived
                    fprintf(fid, '%s = %s;\n', m.sourcePath, m.expr);
                end
            end
            
            % Generate Subplots
            for i = 1:length(obj.Plots)
                p = obj.Plots{i};
                fprintf(fid, '\nfigure(%d); ax = subplot(%d, %d, %d); hold(ax, ''on'');\n', p.f, p.r, p.c, p.p);
                if p.isCus
                    fprintf(fid, 'plot(ax, %s, %s, ''LineWidth'', 1.5, ''DisplayName'', ''%s'');\n', p.xExp, p.yExp, p.name);
                else
                    for j = 1:length(p.y)
                        m = obj.DataVars.(p.y{j});
                        % CORRECT X/Y PLOTTING ORDER
                        fprintf(fid, 'plot(ax, %s, %s, ''LineWidth'', %g, ''DisplayName'', ''%s'');\n', obj.DataVars.(p.x).sourcePath, m.sourcePath, m.width, m.label);
                    end
                end
                if p.grid, fprintf(fid, 'grid(ax, ''on'');\n'); end
                if p.leg, fprintf(fid, 'legend(ax, ''show'', ''Interpreter'', ''none'');\n'); end
            end
            %% =========================================================
%% EXPORT EVENTS
%% =========================================================
for i = 1:length(obj.Events)

    e = obj.Events{i};

    fprintf(fid, '\n%% EVENT: %s\n', e.name);

    fprintf(fid, 'figure(%d);\n', e.fig);

    fprintf(fid, 'axList = findall(gcf, ''Type'', ''axes'', ''-not'', ''Tag'', ''legend'');\n');

    fprintf(fid, 'for ax_i = 1:length(axList)\n');

    fprintf(fid, 'ax = axList(ax_i);\n');

    fprintf(fid, 'hold(ax, ''on'');\n');

    fprintf(fid, 'yl = ylim(ax);\n');

    % --------------------------------------------
    % Write event arrays directly
    % --------------------------------------------
    fprintf(fid, 'eventOn = [');

    fprintf(fid, '%g ', e.onT);

    fprintf(fid, '];\n');

    fprintf(fid, 'eventOff = [');

    fprintf(fid, '%g ', e.offT);

    fprintf(fid, '];\n');

    % --------------------------------------------
    % Render loop
    % --------------------------------------------
    fprintf(fid, 'for k = 1:length(eventOn)\n');

    % ON LINE
    fprintf(fid, ...
        'xline(ax, eventOn(k), ''-'', ''ON : %s'', ''Color'', ''g'', ''LineWidth'', 1.5);\n', ...
        e.name);

    % OFF LINE
    fprintf(fid, ...
        'xline(ax, eventOff(k), ''-'', ''OFF : %s'', ''Color'', ''r'', ''LineWidth'', 1.5);\n', ...
        e.name);

    % PATCH
    fprintf(fid, ...
        ['patch(ax, ' ...
        '[eventOn(k) eventOff(k) eventOff(k) eventOn(k)], ' ...
        '[yl(1) yl(1) yl(2) yl(2)], ' ...
        '''%s'', ' ...
        '''FaceAlpha'', %g, ' ...
        '''EdgeColor'', ''none'', ' ...
        '''HandleVisibility'', ''off'');\n'], ...
        e.c, e.alpha);

    fprintf(fid, 'end\n');

    fprintf(fid, 'end\n');

end
            fclose(fid);
        end
        
        % --- Extraction Tool ---
        function actionRenderExtract(obj)
            xKey = obj.UI.extX.Value; yKey = obj.UI.extY.Value;
            if isempty(xKey) || isempty(yKey), error('Select X and Y signals.'); end
            
            xV = obj.fetchSignal(xKey); yV = obj.fetchSignal(yKey);
            len = min(length(xV), length(yV));
            ax = obj.UI.extAxes; cla(ax);
            
            plot(ax, xV(1:len), yV(1:len), 'ButtonDownFcn', @(~,ev)obj.actionExtractClick(ev));
            grid(ax, 'on'); xlabel(ax, obj.DataVars.(xKey).label, 'Interpreter','none'); ylabel(ax, obj.DataVars.(yKey).label, 'Interpreter','none');
            
            obj.ExtState.xData = xV(1:len);
            obj.ExtState.startX = NaN; obj.ExtState.endX = NaN; obj.ExtState.startIdx = NaN; obj.ExtState.endIdx = NaN;
            obj.UI.lblExtStart.Text = 'Start: NaN'; obj.UI.lblExtEnd.Text = 'End: NaN';
        end
        
        function actionEnableExtCursor(obj)
            obj.logMessage('INFO', 'Click on the plotted blue line to set a marker.');
        end
        
        function actionExtractClick(obj, ev)
            xClick = ev.IntersectionPoint(1);
            [~, idx] = min(abs(obj.ExtState.xData - xClick)); % Horizontal nearest snap
            xSnap = obj.ExtState.xData(idx);
            
            if isnan(obj.ExtState.startX) || (~isnan(obj.ExtState.startX) && ~isnan(obj.ExtState.endX))
                obj.ExtState.startX = xSnap; obj.ExtState.startIdx = idx;
                obj.ExtState.endX = NaN; obj.ExtState.endIdx = NaN;
                if isgraphics(obj.ExtState.hStart), delete(obj.ExtState.hStart); end
                if isgraphics(obj.ExtState.hEnd), delete(obj.ExtState.hEnd); end
                hold(obj.UI.extAxes, 'on');
                obj.ExtState.hStart = xline(obj.UI.extAxes, xSnap, '-g', 'LineWidth', 2, 'Label', 'Start');
                obj.UI.lblExtStart.Text = sprintf('Start: Idx %d (X=%.2f)', idx, xSnap);
                obj.UI.lblExtEnd.Text = 'End: NaN';
            else
                obj.ExtState.endX = xSnap; obj.ExtState.endIdx = idx;
                if obj.ExtState.endIdx < obj.ExtState.startIdx % Swap if backwards
                    [obj.ExtState.startX, obj.ExtState.endX] = deal(obj.ExtState.endX, obj.ExtState.startX);
                    [obj.ExtState.startIdx, obj.ExtState.endIdx] = deal(obj.ExtState.endIdx, obj.ExtState.startIdx);
                    delete(obj.ExtState.hStart);
                    obj.ExtState.hStart = xline(obj.UI.extAxes, obj.ExtState.startX, '-g', 'LineWidth', 2, 'Label', 'Start');
                end
                if isgraphics(obj.ExtState.hEnd), delete(obj.ExtState.hEnd); end
                obj.ExtState.hEnd = xline(obj.UI.extAxes, obj.ExtState.endX, '-r', 'LineWidth', 2, 'Label', 'End');
                obj.UI.lblExtStart.Text = sprintf('Start: Idx %d (X=%.2f)', obj.ExtState.startIdx, obj.ExtState.startX);
                obj.UI.lblExtEnd.Text = sprintf('End: Idx %d (X=%.2f)', obj.ExtState.endIdx, obj.ExtState.endX);
            end
        end
        
        function actionExportData(obj)
            if isnan(obj.ExtState.startIdx) || isnan(obj.ExtState.endIdx), error('Set both Start and End markers.'); end
            chans = obj.UI.extExportList.Value;
            if isempty(chans), error('Select channels to export.'); end
            
            fName = obj.UI.extFile.Value;
            fid = fopen(fName, 'w'); if fid == -1, error('Failed to create file.'); end
            
            % Headers
            lbls = cell(1, length(chans));
            for c=1:length(chans), lbls{c} = obj.DataVars.(chans{c}).label; end
            fprintf(fid, '%s\n', strjoin(lbls, ','));
            
            % Write Rows Incrementally (Prevent memory explosion)
            for r = obj.ExtState.startIdx : obj.ExtState.endIdx
                rowVals = cell(1, length(chans));
                for c = 1:length(chans)
                    sig = obj.fetchSignal(chans{c});
                    if r <= length(sig), rowVals{c} = sprintf('%.6f', sig(r)); else, rowVals{c} = 'NaN'; end
                end
                fprintf(fid, '%s\n', strjoin(rowVals, ','));
            end
            fclose(fid);
        end
        
        % --- State Persistence ---
        function actionSaveState(obj)
            [file, path] = uiputfile('*.mat', 'Save State'); if file == 0, return; end
            appState = struct('DataVars', obj.DataVars, 'Plots', {obj.Plots}, 'Events', {obj.Events}, 'LoadedFile', obj.LoadedFile);
            save(fullfile(path, file), 'appState');
        end
        
        function actionLoadState(obj)
            [file, path] = uigetfile('*.mat', 'Load State'); if file == 0, return; end
            tmp = load(fullfile(path, file));
            obj.DataVars = tmp.appState.DataVars;
            obj.Plots = tmp.appState.Plots;
            obj.Events = tmp.appState.Events;
            obj.LoadedFile = tmp.appState.LoadedFile;
            
            obj.actionRefreshTable();
            obj.syncUILists();
            obj.syncManifest();
            obj.renderAll();
        end
    end
end



