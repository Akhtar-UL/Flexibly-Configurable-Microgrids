function ModularEMSGUI
% Main GUI and EMS workflow.
% - Avoid "clear all" inside GUIs (it can clear UI functions like uilabel).
close all;

% % Input Data
evalin('base', 'load Elec_Price.txt');
evalin('base', 'load Elec_SellPrice.txt');
evalin('base', 'load P_PV1.txt');
evalin('base', 'load P_PV2.txt');
evalin('base', 'load P_WT1.txt');
evalin('base', 'load P_WT2.txt');
evalin('base', 'load P_CL1.txt');
evalin('base', 'load P_NL1.txt');
evalin('base', 'load P_CL2.txt');
evalin('base', 'load P_NL2.txt');

% % Parameters
alpha = 1135.6;
beta = 301.03;
gamma = 0.39;
M_power = 20;

% ---------------------- Microturbines ----------------------
% AC side
N_MT_AC = 1;
MT_AC_fuel = repmat({'Gas'}, 1, N_MT_AC); % Gas, Diesel, Hydrogen
MT_AC_alpha = alpha * ones(1, N_MT_AC);
MT_AC_beta  = beta  * ones(1, N_MT_AC);
MT_AC_gamma = gamma * ones(1, N_MT_AC);
MT_AC_Pmax  = M_power * ones(1, N_MT_AC);

% DC side
N_MT_DC = 1;
MT_DC_fuel  = repmat({'Gas'}, 1, N_MT_DC); % Gas, Diesel, Hydrogen
MT_DC_alpha = alpha * ones(1, N_MT_DC);
MT_DC_beta  = beta  * ones(1, N_MT_DC);
MT_DC_gamma = gamma * ones(1, N_MT_DC);
MT_DC_Pmax  = M_power * ones(1, N_MT_DC);

% Aggregate values for the existing optimizer block (keeps backward compatibility)
alpha2   = mean(MT_DC_alpha);
beta2    = mean(MT_DC_beta);
gamma2   = mean(MT_DC_gamma);
M_power2 = sum(MT_DC_Pmax);

% Renewable generation capacity
PV1_Max=30;
PV2_Max=40;
WT1_Max=40;
WT2_Max=30;

t = 1/4;                    % Time interval [h]
Num_var = 24/t;             % Number of variables
P_grid_max = 80;            % Maximum grid power [kW]
P_conv_max = 100;           % Maximum AC-DC converter power [kW]
Eff_conv = 0.95;            % Converter efficiency

% BESS parameters 1 refers to AC side 2 refers to DC side 
P_BESS1_max = 10;           % Maximum BESS1 power [kW]
P_BESS2_max = 10;           % Maximum BESS2 power [kW]
Eff_BESS1 = 0.9;            % BESS efficiency
Eff_BESS2 = 0.95;           % BESS efficiency
SOC1_max = 90;              % Maximum SOC [%]
SOC1_min = 10;              % Minimum SOC [%]
SOC2_max = 90;              % Maximum SOC [%]
SOC2_min = 10;              % Minimum SOC [%]
CAP1 = 85;                  % Capacity 1 [kWh]
CAP2 = 100;                 % Capacity 2 [kWh]
SOC1_init = 50;             % Initial SOC [%]
SOC2_init = 50;             % Initial SOC [%]

% EV parameters 1 refers to AC side 2 refers to DC side 
P_EV1_max = 11;
P_EV2_max = 11;
Eff_EV1 = 0.9;              % BESS(PCS)
Eff_EV2 = 0.95;             % BESS(PCS)
EV1SOC_max = 90;            % EV1 max SOC [%]
EV1SOC_min = 10;            % EV1 min SOC [%]
EV2SOC_max = 90;            % EV2 max SOC [%]
EV2SOC_min = 10;            % EV2 max SOC [%]
EV_CAP1 = 46;
EV_CAP2 = 68;
EV1_SOCT = 80;
EV2_SOCT = 70;
EV1SOC_init = 30;
EV2SOC_init = 40;

% EV arrival and departure times: 1 refers to AC side 2 refers to DC side 
Ta1=8;
Td1=17;
Ta2=7;
Td2=20;

% --- Multi-EV support (AC side) ---
NEV_AC = 1;
NEV_DC = 1; % number of EVs on DC side (fleet)

Eff_EV_AC     = Eff_EV1*ones(NEV_AC,1);
P_EV_AC_max   = P_EV1_max*ones(NEV_AC,1);
EV_AC_CAP     = EV_CAP1*ones(NEV_AC,1);
EV_AC_SOC_init= EV1SOC_init*ones(NEV_AC,1);
EV_AC_SOC_min = EV1SOC_min*ones(NEV_AC,1);
EV_AC_SOC_max = EV1SOC_max*ones(NEV_AC,1);
EV_AC_SOCT    = EV1_SOCT*ones(NEV_AC,1);
EV_AC_Ta      = Ta1*ones(NEV_AC,1);
EV_AC_Td      = Td1*ones(NEV_AC,1);
EV_AC_status_vec = ones(NEV_AC,1); % will be updated at runtime from EV_AC_status

% ---------------------- Penalty settings ----------------------
% If these penalties are too low relative to generation costs (especially
% fixed/commitment costs), the optimizer may prefer shedding even when
% Units: $/kWh (cost term multiplies dt * power[kW]).
Pen_P_CL1 = 1e5*ones(Num_var,1);   % Critical load shedding penalty (AC)
Pen_P_NL1 = 5e4*ones(Num_var,1);   % Non-critical load shedding penalty (AC)
Pen_P_CL2 = 1e5*ones(Num_var,1);   % Critical load shedding penalty (DC)
Pen_P_NL2 = 5e4*ones(Num_var,1);   % Non-critical load shedding penalty (DC)
Pen_PV1 = 100*ones(Num_var,1);
Pen_PV2 = 100*ones(Num_var,1);
Pen_Wind1 = 100*ones(Num_var,1); 
Pen_Wind2 = 100*ones(Num_var,1); 

% % GUI
fig = uifigure('Name', 'Modular EMS — AC/DC Hybrid Microgrid', 'Position', [80, 80, 1280, 702], 'Color', 'white');
fig.AutoResizeChildren = 'off';

F_S = 14;
set(fig, 'DefaultAxesFontSize', F_S);
set(fig, 'DefaultUIControlFontSize', 14);

% Header
lblTitle = uilabel(fig, 'Text', 'Modular EMS — AC/DC Hybrid Microgrid', ...
    'FontSize', 16, 'FontWeight', 'bold', 'Position', [20, 672, 1240, 22]);

% Panels are drawn behind controls to group AC side, DC side, and Grid/ILC.
panelAC = uipanel(fig, 'Title', 'AC Side Components', 'FontSize', 14, ...
    'Position', [15, 385, 280, 225], 'BackgroundColor', 'white', 'Scrollable', 'off');
panelDC = uipanel(fig, 'Title', 'DC Side Components', 'FontSize', 14, ...
    'Position', [15, 200, 280, 210], 'BackgroundColor', 'white', 'Scrollable', 'off');

try
    panelAC.Units = 'pixels'; panelDC.Units = 'pixels';
    gapPanels = 10;
    panelDC.Position(2) = panelAC.Position(2) - panelDC.Position(4) - gapPanels;
catch
end
% ---------------------- One-line diagram ----------------------
diagramAx = uiaxes(fig, 'Units','pixels', 'Position', [310, 580, 340, 120], ...
    'XTick',[], 'YTick',[], 'Box','off');
try
    diagramAx.Toolbar.Visible = 'off';
catch
end
try
    diagramAx.Interactions = [];
catch
end
diagramAx.XLim = [0 1];
diagramAx.YLim = [0 1];
diagramAx.Color = 'white';
diagramAx.XColor = 'none';
diagramAx.YColor = 'none';
try, diagramAx.XAxis.Visible = 'off'; end
try, diagramAx.YAxis.Visible = 'off'; end
try, diagramAx.XRuler.Axle.Visible = 'off'; end
try, diagramAx.YRuler.Axle.Visible = 'off'; end
try, diagramAx.XRuler.Visible = 'off'; end
try, diagramAx.YRuler.Visible = 'off'; end

title(diagramAx, 'Microgrid Configuration', 'FontSize', 14, 'FontWeight','bold');
try
    diagramAx.Title.Position(2) = 1.18;
catch
end
hold(diagramAx,'on');
 

yAC = 0.66;
yDC = 0.34;
yTop = 0.92;     % AC devices further from bus
yBoxDC = 0.08;   % DC devices further from bus
plot(diagramAx, [0.10 0.90], [yAC yAC], 'k', 'LineWidth', 2.5);
plot(diagramAx, [0.10 0.90], [yDC yDC], 'k', 'LineWidth', 2.5);
text(diagramAx, 0.92, yAC, 'AC', 'FontWeight','bold', 'FontSize', 13);
text(diagramAx, 0.92, yDC, 'DC', 'FontWeight','bold', 'FontSize', 13);

% Device stubs (small boxes) + connection lines (dashed by default)
diagLines = struct();

% Grid (to AC bus)
diagLines.Grid = drawDevice(diagramAx, 0.14, yTop, 'Grid', yAC);

% ILC (between AC & DC)
diagLines.ILC = plot(diagramAx, [0.50 0.50], [yDC yAC], ':', 'Color',[0.6 0.6 0.6], 'LineWidth', 1.2);
rectangle(diagramAx, 'Position', [0.47 0.47 0.06 0.06], 'FaceColor', 'w', 'EdgeColor', 'k');
text(diagramAx, 0.535, 0.50, 'ILC', 'FontSize', 13);

% AC-side devices (top)  
diagLines.PVAC   = drawDevice(diagramAx, 0.24, yTop, 'PV',   yAC);
diagLines.WTAC   = drawDevice(diagramAx, 0.34, yTop, 'WT',   yAC);
diagLines.MTAC   = drawDevice(diagramAx, 0.44, yTop, 'MT',   yAC);
diagLines.BESSAC = drawDevice(diagramAx, 0.64, yTop, 'BESS', yAC);
diagLines.EVAC   = drawDevice(diagramAx, 0.74, yTop, 'EV',   yAC);
diagLines.LoadAC = drawDevice(diagramAx, 0.84, yTop, 'Load', yAC);

% DC-side devices (bottom)  
diagLines.PVDC   = drawDevice(diagramAx, 0.24, yBoxDC, 'PV',   yDC);
diagLines.WTDC   = drawDevice(diagramAx, 0.34, yBoxDC, 'WT',   yDC);
diagLines.MTDC   = drawDevice(diagramAx, 0.44, yBoxDC, 'MT',   yDC);
diagLines.BESSDC = drawDevice(diagramAx, 0.64, yBoxDC, 'BESS', yDC);
diagLines.EVDC   = drawDevice(diagramAx, 0.74, yBoxDC, 'EV',   yDC);
diagLines.LoadDC = drawDevice(diagramAx, 0.84, yBoxDC, 'Load', yDC);

% DR is connected to the LOAD 
xLoad = 0.84;
boxW = 0.06; boxH = 0.06;
xDR  = 0.95;
yDRAC = yTop;
rectangle(diagramAx, 'Position', [xDR-boxW/2, yDRAC-boxH/2, boxW, boxH], 'FaceColor','w', 'EdgeColor','k');
text(diagramAx, xDR, yDRAC + boxH/2 + 0.02, 'DR', 'FontSize',13, 'HorizontalAlignment','center', 'VerticalAlignment','bottom');
diagLines.DRAC = plot(diagramAx, [xLoad+boxW/2, xDR-boxW/2, xDR-boxW/2], [yTop, yTop, yDRAC], ':', 'Color',[0.6 0.6 0.6], 'LineWidth', 1.2);

yDRDC = yBoxDC;
rectangle(diagramAx, 'Position', [xDR-boxW/2, yDRDC-boxH/2, boxW, boxH], 'FaceColor','w', 'EdgeColor','k');
text(diagramAx, xDR, yDRDC - boxH/2 - 0.02, 'DR', 'FontSize',13, 'HorizontalAlignment','center', 'VerticalAlignment','top');
% DC Load -> DR connection (default grey dotted) using an L-shape
diagLines.DRDC = plot(diagramAx, [xLoad+boxW/2, xDR-boxW/2, xDR-boxW/2], [yBoxDC, yBoxDC, yDRDC], ':', 'Color',[0.6 0.6 0.6], 'LineWidth', 1.2);

uilabel(fig, 'Position', [20, 640, 110, 22], 'Text', 'Grid:', 'FontSize', F_S);
gridStatusField = uicheckbox(fig, 'Text', 'Yes', 'Position', [110, 640, 60, 22], 'FontSize', F_S);
gridCfgBtn = uibutton(fig, 'Position', [175, 640, 90, 24], 'Text', 'Configure…', 'FontSize', 13, ...
    'ButtonPushedFcn', @(~,~) openGridDialog());

uilabel(fig, 'Position', [20, 612, 110, 22], 'Text', 'ILC:', 'FontSize', F_S);
ilcStatusField = uicheckbox(fig, 'Text', 'Yes', 'Position', [110, 612, 60, 22], 'FontSize', F_S);
ilcCfgBtn = uibutton(fig, 'Position', [175, 612, 90, 24], 'Text', 'Configure…', 'FontSize', 13, ...
    'ButtonPushedFcn', @(~,~) openILCDialog());

% ---- Load / AC / DC component controls placed inside panels  ----

% Common geometry inside panels
rowH = 22;
rowGap = 4;
xLbl = 12;
xChk = 100;
xBtn = 160;
lblW = 90;
chkW = 60;
btnW = 90;

% Helper to compute row y (top-down) inside a panel
panelInnerTop = 180; panelInnerTopDC = panelInnerTop - 22;  

% ===== AC panel rows =====
y = panelInnerTop;

% Load (AC)
uilabel(panelAC, 'Position', [xLbl, y, lblW, rowH], 'Text', 'Load:', 'FontSize', F_S);
loadACCfgBtn = uibutton(panelAC, 'Position', [xBtn, y-1, btnW, rowH+2], 'Text', 'Configure…', ...
    'FontSize', 13, 'Enable', 'off', ...
    'ButtonPushedFcn', @(~,~) openLoadDialog('AC', []));
loadACStatusField = uicheckbox(panelAC, 'Text', 'Yes', 'Position', [xChk, y, chkW, rowH], ...
    'Value', false, 'Enable', 'on', 'FontSize', F_S, ...
    'ValueChangedFcn', @(src,~) onCompToggle(src, loadACCfgBtn, diagLines.LoadAC));
y = y - (rowH + rowGap);

% PV (AC)
uilabel(panelAC, 'Position', [xLbl, y, lblW, rowH], 'Text', 'PV:', 'FontSize', F_S);
pvACStatusField = uicheckbox(panelAC, 'Text', 'Yes', 'Position', [xChk, y, chkW, rowH], 'Value', false, 'FontSize', F_S);
pvAcCfgBtn = uibutton(panelAC, 'Position', [xBtn, y-1, btnW, rowH+2], 'Text', 'Configure…', 'FontSize', 13, ...
    'ButtonPushedFcn', @(~,~) openPVDialog('AC'));
y = y - (rowH + rowGap);

% WT (AC)
uilabel(panelAC, 'Position', [xLbl, y, lblW, rowH], 'Text', 'WT:', 'FontSize', F_S);
windACStatusField = uicheckbox(panelAC, 'Text', 'Yes', 'Position', [xChk, y, chkW, rowH], 'Value', false, 'FontSize', F_S);
windAcCfgBtn = uibutton(panelAC, 'Position', [xBtn, y-1, btnW, rowH+2], 'Text', 'Configure…', 'FontSize', 13, ...
    'ButtonPushedFcn', @(~,~) openWTDialog('AC'));
y = y - (rowH + rowGap);

% MT (AC)
uilabel(panelAC, 'Position', [xLbl, y, lblW, rowH], 'Text', 'MT:', 'FontSize', F_S);
cdgStatusField = uicheckbox(panelAC, 'Text', 'Yes', 'Position', [xChk, y, chkW, rowH], 'Value', false, 'FontSize', F_S);
cdgCfgBtn = uibutton(panelAC, 'Position', [xBtn, y-1, btnW, rowH+2], 'Text', 'Configure…', 'FontSize', 13, ...
    'ButtonPushedFcn', @(~,~) openCDGDialog());
y = y - (rowH + rowGap);

% BESS (AC)
uilabel(panelAC, 'Position', [xLbl, y, lblW, rowH], 'Text', 'BESS:', 'FontSize', F_S);
bessACStatusField = uicheckbox(panelAC, 'Text', 'Yes', 'Position', [xChk, y, chkW, rowH], 'Value', false, 'FontSize', F_S);
bessAcCfgBtn = uibutton(panelAC, 'Position', [xBtn, y-1, btnW, rowH+2], 'Text', 'Configure…', 'FontSize', 13, ...
    'ButtonPushedFcn', @(~,~) openBESSDialog('AC'));
y = y - (rowH + rowGap);

% EV (AC)
uilabel(panelAC, 'Position', [xLbl, y, lblW, rowH], 'Text', 'EV:', 'FontSize', F_S);
evACStatusField = uicheckbox(panelAC, 'Text', 'Yes', 'Position', [xChk, y, chkW, rowH], 'Value', false, 'FontSize', F_S);
evAcCfgBtn = uibutton(panelAC, 'Position', [xBtn, y-1, btnW, rowH+2], 'Text', 'Configure…', 'FontSize', 13, ...
    'ButtonPushedFcn', @(~,~) openEVDialog('AC'));
y = y - (rowH + rowGap);

% DR (AC)
uilabel(panelAC, 'Position', [xLbl, y, lblW, rowH], 'Text', 'DR:', 'FontSize', F_S);
drACEnableField = uicheckbox(panelAC, 'Text', 'On', 'Position', [xChk, y, chkW, rowH], 'Value', false, 'FontSize', F_S);
drAcCfgBtn = uibutton(panelAC, 'Position', [xBtn, y-1, btnW, rowH+2], 'Text', 'Configure…', 'FontSize', 13, ...
    'ButtonPushedFcn', @(~,~) openDRDialog('AC'));

% ===== DC panel rows =====
y = panelInnerTopDC;

% Load (DC)
uilabel(panelDC, 'Position', [xLbl, y, lblW, rowH], 'Text', 'Load:', 'FontSize', F_S);
loadDCCfgBtn = uibutton(panelDC, 'Position', [xBtn, y-1, btnW, rowH+2], 'Text', 'Configure…', ...
    'FontSize', 13, 'Enable', 'off', ...
    'ButtonPushedFcn', @(~,~) openLoadDialog('DC', []));
loadDCStatusField = uicheckbox(panelDC, 'Text', 'Yes', 'Position', [xChk, y, chkW, rowH], ...
    'Value', false, 'Enable', 'on', 'FontSize', F_S, ...
    'ValueChangedFcn', @(src,~) onCompToggle(src, loadDCCfgBtn, diagLines.LoadDC));
y = y - (rowH + rowGap);

% PV (DC)
uilabel(panelDC, 'Position', [xLbl, y, lblW, rowH], 'Text', 'PV:', 'FontSize', F_S);
pvDCStatusField = uicheckbox(panelDC, 'Text', 'Yes', 'Position', [xChk, y, chkW, rowH], 'Value', false, 'FontSize', F_S);
pvDcCfgBtn = uibutton(panelDC, 'Position', [xBtn, y-1, btnW, rowH+2], 'Text', 'Configure…', 'FontSize', 13, ...
    'ButtonPushedFcn', @(~,~) openPVDialog('DC'));
y = y - (rowH + rowGap);

% WT (DC)
uilabel(panelDC, 'Position', [xLbl, y, lblW, rowH], 'Text', 'WT:', 'FontSize', F_S);
windDCStatusField = uicheckbox(panelDC, 'Text', 'Yes', 'Position', [xChk, y, chkW, rowH], 'Value', false, 'FontSize', F_S);
windDcCfgBtn = uibutton(panelDC, 'Position', [xBtn, y-1, btnW, rowH+2], 'Text', 'Configure…', 'FontSize', 13, ...
    'ButtonPushedFcn', @(~,~) openWTDialog('DC'));
y = y - (rowH + rowGap);

% MT (DC)
uilabel(panelDC, 'Position', [xLbl, y, lblW, rowH], 'Text', 'MT:', 'FontSize', F_S);
mt2StatusField = uicheckbox(panelDC, 'Text', 'Yes', 'Position', [xChk, y, chkW, rowH], 'Value', false, 'FontSize', F_S);
mt2CfgBtn = uibutton(panelDC, 'Position', [xBtn, y-1, btnW, rowH+2], 'Text', 'Configure…', 'FontSize', 13, ...
    'ButtonPushedFcn', @(~,~) openMT2Dialog());
y = y - (rowH + rowGap);

% BESS (DC)
uilabel(panelDC, 'Position', [xLbl, y, lblW, rowH], 'Text', 'BESS:', 'FontSize', F_S);
bessDCStatusField = uicheckbox(panelDC, 'Text', 'Yes', 'Position', [xChk, y, chkW, rowH], 'Value', false, 'FontSize', F_S);
bessDcCfgBtn = uibutton(panelDC, 'Position', [xBtn, y-1, btnW, rowH+2], 'Text', 'Configure…', 'FontSize', 13, ...
    'ButtonPushedFcn', @(~,~) openBESSDialog('DC'));
y = y - (rowH + rowGap);

% EV (DC)
uilabel(panelDC, 'Position', [xLbl, y, lblW, rowH], 'Text', 'EV:', 'FontSize', F_S);
evDCStatusField = uicheckbox(panelDC, 'Text', 'Yes', 'Position', [xChk, y, chkW, rowH], 'Value', false, 'FontSize', F_S);
evDcCfgBtn = uibutton(panelDC, 'Position', [xBtn, y-1, btnW, rowH+2], 'Text', 'Configure…', 'FontSize', 13, ...
    'ButtonPushedFcn', @(~,~) openEVDialog('DC'));
y = y - (rowH + rowGap);

% DR (DC)
uilabel(panelDC, 'Position', [xLbl, y, lblW, rowH], 'Text', 'DR:', 'FontSize', F_S);
drDCEnableField = uicheckbox(panelDC, 'Text', 'On', 'Position', [xChk, y, chkW, rowH], 'Value', false, 'FontSize', F_S);
drDcCfgBtn = uibutton(panelDC, 'Position', [xBtn, y-1, btnW, rowH+2], 'Text', 'Configure…', 'FontSize', 13, ...
    'ButtonPushedFcn', @(~,~) openDRDialog('DC'));

% --- Alias Configure button handles ---
pvACCfgBtn   = pvAcCfgBtn;
windACCfgBtn = windAcCfgBtn;
bessACCfgBtn = bessAcCfgBtn;
evACCfgBtn   = evAcCfgBtn;
drACCfgBtn   = drAcCfgBtn;

pvDCCfgBtn   = pvDcCfgBtn;
windDCCfgBtn = windDcCfgBtn;
bessDCCfgBtn = bessDcCfgBtn;
evDCCfgBtn   = evDcCfgBtn;
drDCCfgBtn   = drDcCfgBtn;

% ---- PV uncertainty settings  ----
if isempty(getappdata(fig,'pv_unc'))
    pv_unc = struct();
    pv_unc.AC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6);
    pv_unc.DC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6);
    setappdata(fig,'pv_unc', pv_unc);
end

% ---- WT uncertainty settings  ----
if isempty(getappdata(fig,'wt_unc'))
    wt_unc = struct();
    wt_unc.AC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6);
    wt_unc.DC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6);
    setappdata(fig,'wt_unc', wt_unc);
end

% ---- Load uncertainty settings ----
if isempty(getappdata(fig,'load_unc'))
    load_unc = struct();
    load_unc.AC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6,'crit_pct',30);
    load_unc.DC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6,'crit_pct',30);
    setappdata(fig,'load_unc', load_unc);
end


% DR (AC) hidden parameter holders (popup)
drACPctField = uieditfield(fig, 'numeric', 'Value', 30, 'Limits', [0 100], 'Position', [-1000, -1000, 60, 22], ...
    'FontSize', 13, 'Editable','on', 'Visible','off');
drACFlexField = uieditfield(fig, 'numeric', 'Value', 1, 'Limits', [0 2], 'Position', [-1000, -1000, 60, 22], ...
    'FontSize', 13, 'Editable','on', 'Visible','off');
drACLambdaField = uieditfield(fig, 'numeric', 'Value', 0.05, 'Limits', [0 inf], 'Position', [-1000, -1000, 60, 22], ...
    'FontSize', 13, 'Editable','on', 'Visible','off');
drACRampFracField = uieditfield(fig, 'numeric', 'Value', 0.5, 'Limits', [0 1], 'Position', [-1000, -1000, 60, 22], ...
    'FontSize', 13, 'Editable','on', 'Visible','off');

drDCPctField = uieditfield(fig, 'numeric', 'Value', 30, 'Limits', [0 100], 'Position', [-1000, -1000, 60, 22], ...
    'FontSize', 13, 'Editable','on', 'Visible','off');
drDCFlexField = uieditfield(fig, 'numeric', 'Value', 1, 'Limits', [0 2], 'Position', [-1000, -1000, 60, 22], ...
    'FontSize', 13, 'Editable','on', 'Visible','off');
drDCLambdaField = uieditfield(fig, 'numeric', 'Value', 0.05, 'Limits', [0 inf], 'Position', [-1000, -1000, 60, 22], ...
    'FontSize', 13, 'Editable','on', 'Visible','off');
drDCRampFracField = uieditfield(fig, 'numeric', 'Value', 0.5, 'Limits', [0 1], 'Position', [-1000, -1000, 60, 22], ...
    'FontSize', 13, 'Editable','on', 'Visible','off');

% --- Run / Optimal cost ---
calculateButton = uibutton(fig, 'Position', [15, 162, 150, 30], 'Text', 'Run Optimization', ...
    'ButtonPushedFcn', @(btn, event) calculate_and_plot(), 'FontSize', F_S);

optCostLbl = uilabel(fig, 'Position', [175, 167, 95, 22], 'Text', 'Optimal Cost:', 'FontSize', F_S);

% Text box for displaying the optimal cost result
optCostField = uieditfield(fig, 'text', 'Value', '0.000', 'Editable', 'off', 'Enable','on', ...
    'BackgroundColor',[1 1 1], 'FontColor',[0 0 0], 'Position', [270, 167, 110, 24], 'FontSize', F_S);

try
    panelDC.Units = 'pixels';
    calculateButton.Units = 'pixels';
    optCostLbl.Units = 'pixels';
    optCostField.Units = 'pixels';

    try
        diagramAx.Units = 'pixels';
        dssPanel.Units  = 'pixels';

        btnW = calculateButton.Position(3);
        btnH = calculateButton.Position(4);
        gapY = 10;

        baseX = dssPanel.Position(1); 

        topQSTS = dssPanel.Position(2) + dssPanel.Position(4);
        bottomDiagram = diagramAx.Position(2);

        newY = topQSTS + gapY;                 
        newY = min(newY, bottomDiagram - btnH - gapY);  
        newY = max(10, newY - 18);

        calculateButton.Position = [baseX, newY, btnW, btnH];

        % Optimal Cost 
        yMid = newY + round((btnH-22)/2);
        optCostLbl.Position(1)   = baseX + btnW + 15;
        optCostLbl.Position(2)   = yMid;
        optCostLbl.Position(3)   = 85;
        optCostField.Position(1) = optCostLbl.Position(1) + optCostLbl.Position(3) + 6;
        optCostField.Position(2) = yMid;
        optCostField.Position(3) = 110;
    catch
    end

try, uistack(calculateButton,'top'); end
    try, uistack(optCostLbl,'top'); end
    try, uistack(optCostField,'top'); end
catch
end

try, uistack(calculateButton,'top'); catch, end
try, uistack(optCostLbl,'top'); catch, end
try, uistack(optCostField,'top'); catch, end

% ---------------------- QSTS (OpenDSS-based) ----------------------
dssPanel = uipanel(fig, 'Title', 'QSTS (OpenDSS) — Status: not loaded', ...
    'Position', [310, 300, 340, 250], 'FontSize', 13); 

headerQSTS = uipanel(dssPanel,'Position',[0 0.60 1 0.40],'BorderType','none');
bodyQSTS   = uipanel(dssPanel,'Position',[0 0.00 1 0.60],'BorderType','none');

try, headerQSTS.Visible='on'; bodyQSTS.Visible='on'; catch, end
try, uistack(headerQSTS,'top'); catch, end
try, dssPanel.Visible = 'on'; catch, end
try, uistack(dssPanel,'top'); catch, end
try
    dssPanel.Position(2) = panelDC.Position(2) + 35; 
catch
end

try
    panelDC.Units = 'pixels';
    calculateButton.Units = 'pixels';
    optCostLbl.Units = 'pixels';
    optCostField.Units = 'pixels';

    try
        diagramAx.Units = 'pixels';
        dssPanel.Units  = 'pixels';

        btnW = calculateButton.Position(3);
        btnH = calculateButton.Position(4);
        gapY = 10;

        baseX = dssPanel.Position(1); 

        topQSTS = dssPanel.Position(2) + dssPanel.Position(4);
        bottomDiagram = diagramAx.Position(2);

        newY = topQSTS + gapY;                
        newY = min(newY, bottomDiagram - btnH - gapY);  
        newY = max(10, newY - 18);

        calculateButton.Position = [baseX, newY, btnW, btnH];

        yMid = newY + round((btnH-22)/2);
        optCostLbl.Position(1)   = baseX + btnW + 15;
        optCostLbl.Position(2)   = yMid;
        optCostLbl.Position(3)   = 85;
        optCostField.Position(1) = optCostLbl.Position(1) + optCostLbl.Position(3) + 6;
        optCostField.Position(2) = yMid;
        optCostField.Position(3) = 110;
    catch
    end

catch
end

% --- QSTS header controls (normalized ) ---
dssSystemLbl = uilabel(headerQSTS,'Text','Test system:','Position',[0.03 0.60 0.25 0.28],'FontSize',12);
dssSystemDD  = uidropdown(headerQSTS,'Items', {'Select system','IEEE 13','IEEE 34','IEEE 123','Real System'},'Value','Select system', ...
    'Position',[0.28 0.60 0.22 0.32],'FontSize',12,'ValueChangedFcn',@(~,~) loadDSSFeeder());

dssBusLbl = uilabel(headerQSTS,'Text','PCC bus:','Position',[0.52 0.60 0.18 0.28],'FontSize',12);
dssBusDD  = uidropdown(headerQSTS,'Items',{'(loading...)'},'Value','(loading...)', ...
    'Position',[0.70 0.60 0.27 0.32],'FontSize',12,'ValueChangedFcn',@(~,~) updatePCCInfo());

dssTimeLbl   = uilabel(headerQSTS,'Text','t (for voltages):','Position',[0.03 0.15 0.22 0.28],'FontSize',12);
dssTimeField = uieditfield(headerQSTS,'numeric','Value',1,'Limits',[1 Inf], ...
    'Position',[0.25 0.12 0.12 0.34],'FontSize',12);

dssRunBtn = uibutton(headerQSTS,'Text','Run QSTS','Position',[0.40 0.10 0.18 0.38], ...
    'ButtonPushedFcn',@(~,~) runOpenDSSValidation(), 'FontSize',12);
dssRunBtn.Enable = 'off';

% Summary table
dssTable = uitable(bodyQSTS, 'Position', [10, 10, max(220, dssPanel.Position(3)-20), 150], ...
    'ColumnName', {'Metric','Value'}, ...
    'RowName', [], ...
    'Data', {'Vmin (pu)','-'; 'Vmax (pu)','-'; 'Max line loading (%)','-'; 'Max trx loading (%)','-'; 'Losses (kW)','-'}, ...
    'ColumnWidth', {'auto','auto'}); 

% QSTS status line (
try
    bodyH = round(dssPanel.Position(4)*0.60);           
    bodyW = max(50, dssPanel.Position(3));             
catch
    bodyH = 150; bodyW = 340;
end
qstsStatusLbl = uilabel(bodyQSTS, 'Text', 'QSTS Analysis: | Status: not loaded', ...
    'Position', [10, bodyH+0, max(10,bodyW-20), 18], ...
    'FontSize', 11, 'FontWeight', 'bold');
try, uistack(qstsStatusLbl,'top'); catch, end

function setQSTSStatus(msg)
    try
        sys = '';
        try, sys = dssSystemDD.Value; catch, end
        if contains(msg,'Test system:')
            fullMsg = msg;
        else
            if isempty(sys), sys = '(none)'; end
            fullMsg = sprintf('Test system: %s | %s', sys, msg);
        end
    catch
        fullMsg = msg;
    end

    try
        dssPanel.Title = ['QSTS (OpenDSS) — ' fullMsg];
    catch
    end

    try
        if exist('qstsStatusLbl','var') && isgraphics(qstsStatusLbl)
            qstsStatusLbl.Text = fullMsg;
            try, uistack(qstsStatusLbl,'top'); catch, end
        end
    catch
    end
end

% Internal storage for feeder paths
dssMasterPath13 = fullfile(pwd, 'OpenDSS_FeederLibrary', 'IEEE13', 'Master.dss');
dssMasterPath34 = fullfile(pwd, 'OpenDSS_FeederLibrary', 'IEEE34', 'Master.dss');
dssMasterPath123 = fullfile(pwd, 'OpenDSS_FeederLibrary', 'IEEE123', 'Master_noLC.dss');
dssMasterPathIowa = fullfile(pwd, 'OpenDSS_FeederLibrary', 'RealSys', 'Master.dss');
setappdata(fig,'dssMasterPath','');
setappdata(fig,'dssBusList', {});
% -------------------------------------------------------------------------

% Keep Configure buttons enabled only when the corresponding component is enabled
% + Update the microgrid diagram (dashed <-> solid connections)
gridStatusField.ValueChangedFcn   = @(src,~) onCompToggle(src, gridCfgBtn, diagLines.Grid);
pvACStatusField.ValueChangedFcn   = @(src,~) onCompToggle(src, pvAcCfgBtn, diagLines.PVAC);
pvDCStatusField.ValueChangedFcn   = @(src,~) onCompToggle(src, pvDcCfgBtn, diagLines.PVDC);
windACStatusField.ValueChangedFcn = @(src,~) onCompToggle(src, windAcCfgBtn, diagLines.WTAC);
windDCStatusField.ValueChangedFcn = @(src,~) onCompToggle(src, windDcCfgBtn, diagLines.WTDC);
cdgStatusField.ValueChangedFcn    = @(src,~) onCompToggle(src, cdgCfgBtn, diagLines.MTAC);
mt2StatusField.ValueChangedFcn    = @(src,~) onCompToggle(src, mt2CfgBtn, diagLines.MTDC);
bessACStatusField.ValueChangedFcn = @(src,~) onCompToggle(src, bessAcCfgBtn, diagLines.BESSAC);
bessDCStatusField.ValueChangedFcn = @(src,~) onCompToggle(src, bessDcCfgBtn, diagLines.BESSDC);
evACStatusField.ValueChangedFcn   = @(src,~) onCompToggle(src, evAcCfgBtn, diagLines.EVAC);
evDCStatusField.ValueChangedFcn   = @(src,~) onCompToggle(src, evDcCfgBtn, diagLines.EVDC);
ilcStatusField.ValueChangedFcn    = @(src,~) onCompToggle(src, ilcCfgBtn, diagLines.ILC);

drACEnableField.ValueChangedFcn = @(~,~) refreshDRControls();
drDCEnableField.ValueChangedFcn = @(~,~) refreshDRControls();
if exist('drACPctField','var') && isgraphics(drACPctField) && isprop(drACPctField,'ValueChangedFcn')
    drACPctField.ValueChangedFcn = @(~,~) refreshDRControls();
end
if exist('drDCPctField','var') && isgraphics(drDCPctField) && isprop(drDCPctField,'ValueChangedFcn')
    drDCPctField.ValueChangedFcn = @(~,~) refreshDRControls();
end

refreshConfigButtons();
refreshDRControls();

% Initial sync of diagram connections with checkbox states
try
    updateConnection(diagLines.Grid,  getUIValue(gridStatusField,0));
    updateConnection(diagLines.ILC,   getUIValue(ilcStatusField,0));
    updateConnection(diagLines.LoadAC,getUIValue(loadACStatusField,0));
    updateConnection(diagLines.PVAC,  getUIValue(pvACStatusField,0));
    updateConnection(diagLines.WTAC,  getUIValue(windACStatusField,0));
    updateConnection(diagLines.MTAC,  getUIValue(cdgStatusField,0));
    updateConnection(diagLines.BESSAC,getUIValue(bessACStatusField,0));
    updateConnection(diagLines.EVAC,  getUIValue(evACStatusField,0));
    updateConnection(diagLines.LoadDC,getUIValue(loadDCStatusField,0));
    updateConnection(diagLines.PVDC,  getUIValue(pvDCStatusField,0));
    updateConnection(diagLines.WTDC,  getUIValue(windDCStatusField,0));
    updateConnection(diagLines.MTDC,  getUIValue(mt2StatusField,0));
    updateConnection(diagLines.BESSDC,getUIValue(bessDCStatusField,0));
    updateConnection(diagLines.EVDC,  getUIValue(evDCStatusField,0));
catch
end
try
    loadACCfgBtn.Enable = onoff(getUIValue(loadACStatusField,0));
    loadDCCfgBtn.Enable = onoff(getUIValue(loadDCStatusField,0));
catch
end

optimizationParametersPanel = uipanel(fig, 'Title', 'Parameters', 'Position', [220, 470, 830, 320], 'FontSize', F_S, 'Visible','off');
uilabel(fig, 'Position', [250, 710, 150, 22], 'Text', 'Power (kW):', 'FontSize', F_S);
PGridMaxField = uieditfield(fig, 'numeric', 'Value', P_grid_max, 'Position', [350, 710, 50, 22], 'FontSize', F_S);

resultPanel = uipanel(fig, 'Title', '', 'Position', [650, 420, 250, 40], 'FontSize', F_S, 'Visible','off');

uilabel(resultPanel, 'Position', [10, 10, 150, 22], 'Text', 'Optimal Cost(₩):', 'FontSize', F_S);
resultLabel = uilabel(resultPanel, 'Position', [150, 10, 250, 22], 'Text', '', 'FontSize', F_S);

% Editing into popups
    function refreshConfigButtons()
        
try
    if exist('gridStatusField','var') && isgraphics(gridStatusField) && exist('gridCfgBtn','var') && isgraphics(gridCfgBtn)
        gridCfgBtn.Enable = ternEnable(gridStatusField.Value);
    end
    if exist('ilcStatusField','var') && isgraphics(ilcStatusField) && exist('ilcCfgBtn','var') && isgraphics(ilcCfgBtn)
        ilcCfgBtn.Enable = ternEnable(ilcStatusField.Value);
    end

    if exist('loadACStatusField','var') && isgraphics(loadACStatusField) && exist('loadACCfgBtn','var') && isgraphics(loadACCfgBtn)
        loadACCfgBtn.Enable = ternEnable(loadACStatusField.Value);
    end
    if exist('loadDCStatusField','var') && isgraphics(loadDCStatusField) && exist('loadDCCfgBtn','var') && isgraphics(loadDCCfgBtn)
        loadDCCfgBtn.Enable = ternEnable(loadDCStatusField.Value);
    end

    if exist('pvACStatusField','var') && isgraphics(pvACStatusField) && exist('pvAcCfgBtn','var') && isgraphics(pvAcCfgBtn)
        pvAcCfgBtn.Enable = ternEnable(pvACStatusField.Value);
    end
    if exist('pvDCStatusField','var') && isgraphics(pvDCStatusField) && exist('pvDcCfgBtn','var') && isgraphics(pvDcCfgBtn)
        pvDcCfgBtn.Enable = ternEnable(pvDCStatusField.Value);
    end

    if exist('windACStatusField','var') && isgraphics(windACStatusField) && exist('windAcCfgBtn','var') && isgraphics(windAcCfgBtn)
        windAcCfgBtn.Enable = ternEnable(windACStatusField.Value);
    end
    if exist('windDCStatusField','var') && isgraphics(windDCStatusField) && exist('windDcCfgBtn','var') && isgraphics(windDcCfgBtn)
        windDcCfgBtn.Enable = ternEnable(windDCStatusField.Value);
    end

    if exist('cdgStatusField','var') && isgraphics(cdgStatusField) && exist('cdgCfgBtn','var') && isgraphics(cdgCfgBtn)
        cdgCfgBtn.Enable = ternEnable(cdgStatusField.Value);
    end
    if exist('mt2StatusField','var') && isgraphics(mt2StatusField) && exist('mt2CfgBtn','var') && isgraphics(mt2CfgBtn)
        mt2CfgBtn.Enable = ternEnable(mt2StatusField.Value);
    end

    if exist('bessACStatusField','var') && isgraphics(bessACStatusField) && exist('bessAcCfgBtn','var') && isgraphics(bessAcCfgBtn)
        bessAcCfgBtn.Enable = ternEnable(bessACStatusField.Value);
    end
    if exist('bessDCStatusField','var') && isgraphics(bessDCStatusField) && exist('bessDcCfgBtn','var') && isgraphics(bessDcCfgBtn)
        bessDcCfgBtn.Enable = ternEnable(bessDCStatusField.Value);
    end

    if exist('evACStatusField','var') && isgraphics(evACStatusField) && exist('evAcCfgBtn','var') && isgraphics(evAcCfgBtn)
        evAcCfgBtn.Enable = ternEnable(evACStatusField.Value);
    end
    if exist('evDCStatusField','var') && isgraphics(evDCStatusField) && exist('evDcCfgBtn','var') && isgraphics(evDcCfgBtn)
        evDcCfgBtn.Enable = ternEnable(evDCStatusField.Value);
    end

    if exist('drACEnableField','var') && isgraphics(drACEnableField) && exist('drACCfgBtn','var') && isgraphics(drACCfgBtn)
        drACCfgBtn.Enable = ternEnable(drACEnableField.Value);
    end
    if exist('drDCEnableField','var') && isgraphics(drDCEnableField) && exist('drDCCfgBtn','var') && isgraphics(drDCCfgBtn)
        drDCCfgBtn.Enable = ternEnable(drDCEnableField.Value);
    end
catch
end

        
    end

    function refreshDRControls()
        try
            drACCfgBtn.Enable = onoff(getUIValue(drACEnableField, 0));
            drDCCfgBtn.Enable = onoff(getUIValue(drDCEnableField, 0));

            drACPctDispLbl.Text = sprintf('%.0f%%', max(0,min(100,getUIValue(drACPctField,0))));
            drDCPctDispLbl.Text = sprintf('%.0f%%', max(0,min(100,getUIValue(drDCPctField,0))));

            try
                updateConnection(diagLines.DRAC, getUIValue(drACEnableField,0));
                updateConnection(diagLines.DRDC, getUIValue(drDCEnableField,0));
            catch
            end

        catch
        end
    end

    function s = onoff(v)
        if v, s = 'on'; else, s = 'off'; end
    end

    function v = getUIValue(h, defaultVal)
        try
            if isempty(h) || ~isgraphics(h) || ~isprop(h,'Value')
                v = defaultVal;
            else
                v = h.Value;
            end
        catch
            v = defaultVal;
        end
    end
function data = defaultEVACData(n)
    n = max(1, round(n));
    pmax = getUIValue(EV1MaxField, P_EV1_max);
    eff  = getUIValue(EffEV1Field, Eff_EV1);
    cap  = EV_CAP1;
    soc0 = EV1SOC_init;
    socmn= EV1SOC_min;
    socmx= EV1SOC_max;
    soct = getUIValue(EV1SOCTarField, EV1_SOCT);
    ta   = getUIValue(EV1ARRField, Ta1);
    td   = getUIValue(EV1DEPField, Td1);

    row = [pmax, eff, cap, soc0, socmn, socmx, soct, ta, td];
    data = repmat(row, n, 1);
end

function data = defaultEVDCData(n)
    getv = @(nm, fb) localGetCallerVar(nm, fb);

    pmax = getv('P_EV2_max', 11);         % kW
    eff  = getv('Eff_EV2', 0.95);
    cap  = getv('EV_CAP2', 60);           % kWh

    soc0 = getv('EV2SOC_init', 40);
    socm = getv('EV2SOC_min', 10);
    socM = getv('EV2SOC_max', 90);
    soct = getv('EV2_SOCT', 70);

    ta   = getv('Ta2', 7);
    td   = getv('Td2', 20);
    % If user enters an overnight window (td < ta), keep td as-is and let the
    data = repmat({[]}, n, 9);
    for i = 1:n
        data{i,1} = pmax;   % Pmax_kW
        data{i,2} = eff;    % Eff
        data{i,3} = cap;    % Cap_kWh
        data{i,4} = soc0;   % SOC_init
        data{i,5} = socm;   % SOC_min
        data{i,6} = socM;   % SOC_max
        data{i,7} = soct;   % SOC_target
        data{i,8} = ta;     % Arr_h
        data{i,9} = td;     % Dep_h
    end
end

function onNEVACChanged()
    try
        n = max(1, round(getUIValue(NEV_ACField, NEV_AC)));
        NEV_ACField.Value = n;
        NEV_AC = n; 
        if exist('EVACTable','var') && ~isempty(EVACTable) && isgraphics(EVACTable)
            D = EVACTable.Data;
            if isempty(D)
                D = defaultEVACData(n);
            else
                r = size(D,1);
                if r < n
                    D = [D; defaultEVACData(n-r)];
                elseif r > n
                    D = D(1:n, :);
                end
            end
            EVACTable.Data = D;
        end
    catch
    end
end

function onNEVDCChanged()
    try
        n = max(1, round(getUIValue(NEV_DCField, NEV_DC)));
        NEV_DCField.Value = n;
        NEV_DC = n; 
        if exist('EVDCTable','var') && ~isempty(EVDCTable) && isgraphics(EVDCTable)
            D = EVDCTable.Data;
            if isempty(D)
                D = defaultEVDCData(n);
            else
                r = size(D,1);
                if r < n
                    D = [D; defaultEVDCData(n-r)];
                elseif r > n
                    D = D(1:n, :);
                end
            end
            EVDCTable.Data = D;
        end
    catch
    end
end

% Input field for Micro-turbine
uilabel(fig, 'Position', [250, 620, 150, 22], 'Text', 'γ(₩/kW2):', 'FontSize', F_S);
gammaField = uieditfield(fig, 'numeric', 'Value', gamma, 'Position', [350, 620, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [430, 620, 150, 22], 'Text', 'β(₩/kW):', 'FontSize', F_S);
betaField = uieditfield(fig, 'numeric', 'Value', beta, 'Position', [520, 620, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [580, 620, 150, 22], 'Text', 'α(₩):', 'FontSize', F_S);
alphaField = uieditfield(fig, 'numeric', 'Value', alpha, 'Position', [670, 620, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [730, 620, 150, 22], 'Text', 'Power(kW):', 'FontSize', F_S);
powerField = uieditfield(fig, 'numeric', 'Value', M_power, 'Position', [830, 620, 50, 22], 'FontSize', F_S);

% Input field for PVs
uilabel(fig, 'Position', [250, 680, 150, 22], 'Text', 'Power(kW):', 'FontSize', F_S);
PV1maxField = uieditfield(fig, 'numeric', 'Value', PV1_Max, 'Position', [350, 680, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [250, 650, 150, 22], 'Text', 'Power(kW):', 'FontSize', F_S);
PV2maxField = uieditfield(fig, 'numeric', 'Value', PV2_Max, 'Position', [350, 650, 50, 22], 'FontSize', F_S);

% Wind rated power fields (edited via popups)
Wind1maxField = uieditfield(fig, 'numeric', 'Value', WT1_Max, 'Position', [420, 680, 50, 22], 'FontSize', F_S);
Wind2maxField = uieditfield(fig, 'numeric', 'Value', WT2_Max, 'Position', [420, 650, 50, 22], 'FontSize', F_S);

% Input fields for AC BESS parameters
uilabel(fig, 'Position', [250, 590, 150, 22], 'Text', 'SoC L(%):', 'FontSize', F_S);
SOC1MinField = uieditfield(fig, 'numeric', 'Value', SOC1_min, 'Position', [350, 590, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [430, 590, 150, 22], 'Text', 'SoC H(%):', 'FontSize', F_S);
SOC1MaxField = uieditfield(fig, 'numeric', 'Value', SOC1_max, 'Position', [520, 590, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [580, 590, 150, 22], 'Text', 'Cap(kWh):', 'FontSize', F_S);
CAP1Field = uieditfield(fig, 'numeric', 'Value', CAP1, 'Position', [670, 590, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [730, 590, 150, 22], 'Text', 'Power(kW):', 'FontSize', F_S);
PBESS1MaxField = uieditfield(fig, 'numeric', 'Value', P_BESS1_max, 'Position', [830, 590, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [900, 590, 150, 22], 'Text', 'Eff(%):', 'FontSize', F_S);
EffBESS1Field = uieditfield(fig, 'numeric', 'Value', Eff_BESS1, 'Position', [980, 590, 50, 22], 'FontSize', F_S);

% Input fields for DC BESS parameters
uilabel(fig, 'Position', [250, 560, 150, 22], 'Text', 'SoC L(%):', 'FontSize', F_S);
SOC2MinField = uieditfield(fig, 'numeric', 'Value', SOC2_min, 'Position', [350, 560, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [430, 560, 150, 22], 'Text', 'SoC H(%):', 'FontSize', F_S);
SOC2MaxField = uieditfield(fig, 'numeric', 'Value', SOC2_max, 'Position', [520, 560, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [580, 560, 150, 22], 'Text', 'Cap(kWh):', 'FontSize', F_S);
CAP2Field = uieditfield(fig, 'numeric', 'Value', CAP2, 'Position', [670, 560, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [730, 560, 150, 22], 'Text', 'Power(kW):', 'FontSize', F_S);
PBESS2MaxField = uieditfield(fig, 'numeric', 'Value', P_BESS2_max, 'Position', [830, 560, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [900, 560, 150, 22], 'Text', 'Eff(%):', 'FontSize', F_S);
EffBESS2Field = uieditfield(fig, 'numeric', 'Value', Eff_BESS2, 'Position', [980, 560, 50, 22], 'FontSize', F_S);

% Input fields for AC EV parameters
uilabel(fig, 'Position', [250, 530, 150, 22], 'Text', 'SOC T(%):', 'FontSize', F_S);
EV1SOCTarField = uieditfield(fig, 'numeric', 'Value', EV1_SOCT, 'Position', [350, 530, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [430, 530, 150, 22], 'Text', 'Arrive(h):', 'FontSize', F_S);
EV1ARRField = uieditfield(fig, 'numeric', 'Value', Ta1, 'Position', [520, 530, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [580, 530, 150, 22], 'Text', 'Depart(h):', 'FontSize', F_S);
EV1DEPField = uieditfield(fig, 'numeric', 'Value', Td1, 'Position', [670, 530, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [730, 530, 150, 22], 'Text', 'Power(kW):', 'FontSize', F_S);
EV1MaxField = uieditfield(fig, 'numeric', 'Value', P_EV1_max, 'Position', [830, 530, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [900, 530, 150, 22], 'Text', 'Eff(%):', 'FontSize', F_S);
EffEV1Field = uieditfield(fig, 'numeric', 'Value', Eff_EV1, 'Position', [980, 530, 50, 22], 'FontSize', F_S);

% ---- AC EV Fleet controls (multi-EV) ----
uilabel(fig, 'Position', [250, 470, 180, 22], 'Text', 'AC EVs (N):', 'FontSize', F_S, 'Visible','off');
NEV_ACField = uispinner(fig, 'Limits', [1 50], 'Step', 1, 'Value', NEV_AC, ...
    'Position', [350, 470, 70, 22], 'FontSize', F_S, 'Visible','off', 'ValueChangedFcn', @(spn,~)onNEVACChanged());

% Table to edit per-EV parameters (rows = EV index 1..N)
evColNames = {'Pmax_kW','Eff','Cap_kWh','SOC_init','SOC_min','SOC_max','SOC_target','Arr_h','Dep_h'};
EVACTable = uitable(fig, ...
    'Data', defaultEVACData(NEV_AC), ...
    'ColumnName', evColNames, ...
    'ColumnEditable', true(1,numel(evColNames)), ...
    'Position', [250, 305, 780, 155], ...
    'Visible','off', ...
    'FontSize', F_S);

% Hidden controls for DC EV fleet (edited via EV (DC) -> Configure… dialog)
uilabel(fig, 'Position', [250, 275, 180, 22], 'Text', 'DC EVs (N):', 'FontSize', F_S, 'Visible','off');
NEV_DCField = uispinner(fig, 'Limits', [1 50], 'Step', 1, 'Value', NEV_DC, ...
    'Position', [350, 275, 70, 22], 'FontSize', F_S, 'Visible','off', 'ValueChangedFcn', @(spn,~)onNEVDCChanged());

EVDCTable = uitable(fig, ...
    'Data', defaultEVDCData(NEV_DC), ...
    'ColumnName', evColNames, ...
    'ColumnEditable', true(1,numel(evColNames)), ...
    'Position', [250, 115, 780, 155], ...
    'Visible','off', ...
    'FontSize', F_S);

% Input fields for DC EV parameters
uilabel(fig, 'Position', [250, 500, 150, 22], 'Text', 'SoC T(%):', 'FontSize', F_S);
EV2SOCTarField = uieditfield(fig, 'numeric', 'Value', EV2_SOCT, 'Position', [350, 500, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [430, 500, 150, 22], 'Text', 'Arrive(h):', 'FontSize', F_S);
EV2ARRField = uieditfield(fig, 'numeric', 'Value', Ta2, 'Position', [520, 500, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [580, 500, 150, 22], 'Text', 'Depart(h):', 'FontSize', F_S);
EV2DEPField = uieditfield(fig, 'numeric', 'Value', Td2, 'Position', [670, 500, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [730, 500, 150, 22], 'Text', 'Power(kW):', 'FontSize', F_S);
EV2MaxField = uieditfield(fig, 'numeric', 'Value', P_EV2_max, 'Position', [830, 500, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [900, 500, 150, 22], 'Text', 'Eff(%):', 'FontSize', F_S);
EffEV2Field = uieditfield(fig, 'numeric', 'Value', Eff_EV2, 'Position', [980, 500, 50, 22], 'FontSize', F_S);

% Hidden advanced parameters (kept out of the main GUI; edited via popups)
SOC1InitField   = uieditfield(fig,'numeric','Value',SOC1_init,   'Position',[260, 460, 70, 22], 'FontSize', F_S, 'Visible','off');
SOC2InitField   = uieditfield(fig,'numeric','Value',SOC2_init,   'Position',[340, 460, 70, 22], 'FontSize', F_S, 'Visible','off');

EV1CapField     = uieditfield(fig,'numeric','Value',EV_CAP1,     'Position',[420, 460, 70, 22], 'FontSize', F_S, 'Visible','off');
EV2CapField     = uieditfield(fig,'numeric','Value',EV_CAP2,     'Position',[500, 460, 70, 22], 'FontSize', F_S, 'Visible','off');

EV1SOCInitField = uieditfield(fig,'numeric','Value',EV1SOC_init, 'Position',[580, 460, 70, 22], 'FontSize', F_S, 'Visible','off');
EV2SOCInitField = uieditfield(fig,'numeric','Value',EV2SOC_init, 'Position',[660, 460, 70, 22], 'FontSize', F_S, 'Visible','off');

EV1SOCMinField  = uieditfield(fig,'numeric','Value',EV1SOC_min,  'Position',[740, 460, 70, 22], 'FontSize', F_S, 'Visible','off');
EV1SOCMaxField  = uieditfield(fig,'numeric','Value',EV1SOC_max,  'Position',[820, 460, 70, 22], 'FontSize', F_S, 'Visible','off');

EV2SOCMinField  = uieditfield(fig,'numeric','Value',EV2SOC_min,  'Position',[900, 460, 70, 22], 'FontSize', F_S, 'Visible','off');
EV2SOCMaxField  = uieditfield(fig,'numeric','Value',EV2SOC_max,  'Position',[980, 460, 70, 22], 'FontSize', F_S, 'Visible','off');

% Input fields for AC-DC converter parameters
uilabel(fig, 'Position', [250, 470, 150, 22], 'Text', 'Cap(kW):', 'FontSize', F_S);
PConvMaxField = uieditfield(fig, 'numeric', 'Value', P_conv_max, 'Position', [350, 470, 50, 22], 'FontSize', F_S);

uilabel(fig, 'Position', [430, 470, 150, 22], 'Text', 'Eff(%):', 'FontSize', F_S);
EffConvField = uieditfield(fig, 'numeric', 'Value', Eff_conv, 'Position', [520, 470, 50, 22], 'FontSize', F_S);

% Hide the original parameter controls to keep the main GUI uncluttered.
hideParameterControls();


plotPosTop = [0.55, 0.64, 0.42, 0.31];   % placeholder; will be updated by onResize()
plotPosBot = [0.55, 0.24, 0.42, 0.31];   % placeholder; will be updated by onResize()

% Top plot selector
plotViewLabelTop = uilabel(fig, 'Text','Optimization:', 'FontSize', 13, 'HorizontalAlignment','right');
plotViewLabelTop.Position = getPlotLabelPos(fig, plotPosTop);
plotSelectorTop = uidropdown(fig, ...
    'Items', {'Power balance: AC side','Power balance: DC side','SOC: BESS','SOC: EVs','Load Curtailment','Renewables Curtailment','DR: AC load shifting','DR: DC load shifting','Electricity prices','All'}, ...
    'Value', 'Power balance: AC side', ...
    'Position', getPlotSelectorPos(fig, plotPosTop), ...
    'ValueChangedFcn', @(dd,~) renderBoth());

% Bottom plot selector
plotViewLabelBot = uilabel(fig, 'Text','UNC/QSTS:', 'FontSize', 13, 'HorizontalAlignment','right');
plotViewLabelBot.Position = getPlotLabelPos(fig, plotPosBot);
plotSelectorBot = uidropdown(fig, ...
    'Items', {'QSTS: Voltage min/max','QSTS: Bus voltages (t)','QSTS: Node voltages (t)','ROB: PV robust (AC/DC)','ROB: WT robust (AC/DC)','ROB: Load robust (AC/DC)','UNC: PV scenarios (AC)','UNC: PV scenarios (DC)','UNC: WT scenarios (AC)','UNC: WT scenarios (DC)','UNC: Load scenarios (AC)','UNC: Load scenarios (DC)','UNC: Scenarios (All AC/DC)'}, ...
    'Value', 'QSTS: Voltage min/max', ...
    'Position', getPlotSelectorPos(fig, plotPosBot), ...
    'ValueChangedFcn', @(dd,~) renderBoth());

% Plot panels (host axes)
plotPanelTop = uipanel(fig, 'Units','normalized','Position', plotPosTop, 'BorderType','line');
plotPanelBot = uipanel(fig, 'Units','normalized','Position', plotPosBot, 'BorderType','line');
try, renderBoth(); catch, end


% --- Enable Configure buttons only when corresponding component is selected ---
if exist('pvACCfgBtn','var') && isgraphics(pvACCfgBtn), pvACCfgBtn.Enable = onoff(getUIValue(pvACStatusField,0)); end
if exist('pvDCCfgBtn','var') && isgraphics(pvDCCfgBtn), pvDCCfgBtn.Enable = onoff(getUIValue(pvDCStatusField,0)); end
if exist('loadACCfgBtn','var') && isgraphics(loadACCfgBtn), loadACCfgBtn.Enable = onoff(getUIValue(loadACStatusField,0)); end
if exist('loadDCCfgBtn','var') && isgraphics(loadDCCfgBtn), loadDCCfgBtn.Enable = onoff(getUIValue(loadDCStatusField,0)); end
if exist('windACCfgBtn','var') && isgraphics(windACCfgBtn), windACCfgBtn.Enable = onoff(getUIValue(windACStatusField,0)); end
if exist('windDCCfgBtn','var') && isgraphics(windDCCfgBtn), windDCCfgBtn.Enable = onoff(getUIValue(windDCStatusField,0)); end
if exist('cdgCfgBtn','var') && isgraphics(cdgCfgBtn), cdgCfgBtn.Enable = onoff(getUIValue(cdgStatusField,0)); end
if exist('mt2CfgBtn','var') && isgraphics(mt2CfgBtn), mt2CfgBtn.Enable = onoff(getUIValue(mt2StatusField,0)); end
if exist('bessACCfgBtn','var') && isgraphics(bessACCfgBtn), bessACCfgBtn.Enable = onoff(getUIValue(bessACStatusField,0)); end
if exist('bessDCCfgBtn','var') && isgraphics(bessDCCfgBtn), bessDCCfgBtn.Enable = onoff(getUIValue(bessDCStatusField,0)); end
if exist('evACCfgBtn','var') && isgraphics(evACCfgBtn), evACCfgBtn.Enable = onoff(getUIValue(evACStatusField,0)); end
if exist('evDCCfgBtn','var') && isgraphics(evDCCfgBtn), evDCCfgBtn.Enable = onoff(getUIValue(evDCStatusField,0)); end
if exist('drACCfgBtn','var') && isgraphics(drACCfgBtn), drACCfgBtn.Enable = onoff(getUIValue(drACEnableField,0)); end
if exist('drDCCfgBtn','var') && isgraphics(drDCCfgBtn), drDCCfgBtn.Enable = onoff(getUIValue(drDCEnableField,0)); end
if exist('gridCfgBtn','var') && isgraphics(gridCfgBtn), gridCfgBtn.Enable = onoff(getUIValue(gridStatusField,0)); end
if exist('ilcCfgBtn','var') && isgraphics(ilcCfgBtn), ilcCfgBtn.Enable = onoff(getUIValue(ilcStatusField,0)); end

fig.SizeChangedFcn = @(~,~) onResize();

% ---------------------- Enable Configure buttons only when selected ----------------------
onResize();   
renderBoth();

function onResize()
    try
        if ~isvalid(fig); return; end
        fig.Units = 'pixels';
        W = fig.Position(3);
        H = fig.Position(4);

        try
            panelAC.Units = 'pixels';
            panelDC.Units = 'pixels';
            gapPanels = 10;
            panelDC.Position(2) = panelAC.Position(2) - panelDC.Position(4) - gapPanels;
        catch
        end
        try
            panelAC.Units = 'pixels';
            dssPanel.Units = 'pixels';
            diagramAx.Units = 'pixels';
            diagW = dssPanel.Position(3);
            diagH = diagramAx.Position(4);
            diagX = dssPanel.Position(1);
            headerPad = 95;
            diagY = max(panelAC.Position(2) + panelAC.Position(4) - (diagH + 10), H - (diagH + headerPad));
            diagramAx.Position = [diagX, diagY, diagW, diagH];
        catch
        end

        panelDC.Units  = 'pixels';
        dssPanel.Units = 'pixels';
        dssTable.Units = 'pixels';

        dc  = panelDC.Position;   
        gap = 8;                  

    try
        diagramAx.Units = 'pixels';
        dssPanel.Units  = 'pixels';

        btnW = calculateButton.Position(3);
        btnH = calculateButton.Position(4);
        gapY = 10;

        baseX = dssPanel.Position(1); 

        topQSTS = dssPanel.Position(2) + dssPanel.Position(4);
        bottomDiagram = diagramAx.Position(2);

        newY = topQSTS + gapY;                 
        newY = min(newY, bottomDiagram - btnH - gapY);  
        newY = max(10, newY - 18);

        calculateButton.Position = [baseX, newY, btnW, btnH];

        yMid = newY + round((btnH-22)/2);
        optCostLbl.Position(1)   = baseX + btnW + 15;
        optCostLbl.Position(2)   = yMid;
        optCostLbl.Position(3)   = 85;
        optCostField.Position(1) = optCostLbl.Position(1) + optCostLbl.Position(3) + 6;
        optCostField.Position(2) = yMid;
        optCostField.Position(3) = 110;
    catch
    end

try, uistack(calculateButton,'top'); end
            try, uistack(optCostLbl,'top'); end
            try, uistack(optCostField,'top'); end
        catch
        end

        qW = 340;
        qX = dc(1) + dc(3) + gap;
qX = min(qX, W - qW - 10);
        try
            calculateButton.Units = 'pixels';
            optCostLbl.Units     = 'pixels';
            optCostField.Units   = 'pixels';

            yRun = calculateButton.Position(2);
            hRun = calculateButton.Position(4);
            yMid = yRun + round((hRun-22)/2);

            optCostLbl.Position(2)   = yMid;
            optCostField.Position(2) = yMid;
            optCostLbl.Position(1)   = calculateButton.Position(1) + calculateButton.Position(3) + 15;
            optCostLbl.Position(3)   = 85;
            optCostField.Position(1) = optCostLbl.Position(1) + optCostLbl.Position(3) + 6;
            optCostField.Position(3) = 80;

            maxRight = qX - 12;
            if optCostField.Position(1) + optCostField.Position(3) > maxRight
                optCostField.Position(3) = max(55, maxRight - optCostField.Position(1));
            end
            figW = fig.Position(3);
            optCostField.Position(1) = min(optCostField.Position(1), figW - optCostField.Position(3) - 10);
            optCostLbl.Position(1)   = min(optCostLbl.Position(1), optCostField.Position(1) - optCostLbl.Position(3) - 6);
            try, uistack(optCostField,'top'); catch, end
            try, uistack(optCostLbl,'top'); catch, end

        catch
        end

        qTop = dc(2) + dc(4);
        qH   = min(300, max(240, dc(4)));
        qY   = dc(2); 
        qY   = min(qY, H - qH - 10);
        qY   = max(qY, 10);
dssPanel.Position = [qX, qY, qW, qH];

        try
            dssPanel.Units  = 'pixels';
            headerQSTS.Units = 'pixels';
            bodyQSTS.Units   = 'pixels';

            qWpx = dssPanel.Position(3);
            qHpx = dssPanel.Position(4);

            headerH = 72; 
            headerQSTS.Position = [0, qHpx-headerH, qWpx, headerH];
            bodyQSTS.Position   = [0, 0, qWpx, qHpx-headerH];

            row1Y = headerH - 34;
            row2Y = headerH - 62;

            dssSystemLbl.Position = [10, row1Y, 90, 18];
            dssSystemDD.Position  = [80, row1Y-3, 110, 22];
            dssBusLbl.Position    = [200, row1Y, 60, 18];
            dssBusDD.Position     = [260, row1Y-3, 80, 22];

            dssTimeLbl.Position   = [10, row2Y, 95, 18];
            dssTimeField.Position = [100, row2Y-3, 70, 22];
            dssRunBtn.Position    = [180, row2Y-6, 110, 26];

            statusH = 18; topPad = 2; gap = 6;
            try
                qstsStatusLbl.Units = 'pixels';
                qstsStatusLbl.Position = [10, (qHpx-headerH)-topPad-statusH, max(10,qWpx-20), statusH];
                uistack(qstsStatusLbl,'top');
            catch
            end
            dssTable.Units = 'pixels';
            dssTable.Position = [10, 10, max(10,qWpx-20), max(10,(qHpx-headerH)-topPad-statusH-gap-10)];

            dssSystemLbl.Visible='on'; dssSystemDD.Visible='on';
            dssBusLbl.Visible='on';    dssBusDD.Visible='on';
            dssTimeLbl.Visible='on';   dssTimeField.Visible='on'; dssRunBtn.Visible='on';
            try, uistack(dssTable,'bottom'); catch, end
        catch
        end

        try, headerQSTS.Visible='on'; bodyQSTS.Visible='on'; catch, end
        try, uistack(headerQSTS,'top'); catch, end
        
        try, dssPanel.Visible = 'on'; catch, end
        try, uistack(dssPanel,'top'); catch, end
        try
            diagramAx.Units = 'pixels';
            calculateButton.Units = 'pixels';
            optCostLbl.Units = 'pixels';
            optCostField.Units = 'pixels';

            gapY = 8;
            btnH = calculateButton.Position(4);

            diagW = dssPanel.Position(3);
            diagH = diagramAx.Position(4);
            diagX = dssPanel.Position(1);
            headerPad = 95;
            diagY = min(H - (diagH + headerPad), panelAC.Position(2) + panelAC.Position(4) - (diagH + 10));
            diagY = max(diagY, panelAC.Position(2) + 10);
            diagramAx.Position = [diagX, diagY, diagW, diagH];

            try
                calculateButton.Units = 'pixels';
                optCostLbl.Units     = 'pixels';
                optCostField.Units   = 'pixels';
                diagramAx.Units      = 'pixels';
                dssPanel.Units       = 'pixels';

                btnW = calculateButton.Position(3);
                btnH = calculateButton.Position(4);
                gapY = 10;

                baseX = dssPanel.Position(1);

                topQSTS       = dssPanel.Position(2) + dssPanel.Position(4);
                bottomDiagram = diagramAx.Position(2);

                newY = topQSTS + gapY;
                newY = min(newY, bottomDiagram - btnH - gapY);
                newY = max(10, newY - 18);

                calculateButton.Position = [baseX, newY, btnW, btnH];
                calculateButton.Visible  = 'on';

                yMid = newY + round((btnH-22)/2);
                optCostLbl.Position(1)   = baseX + btnW + 15;
                optCostLbl.Position(2)   = yMid;
                optCostLbl.Position(3)   = 85;

                optCostField.Position(1) = optCostLbl.Position(1) + optCostLbl.Position(3) + 6;
                optCostField.Position(2) = yMid;
                optCostField.Position(3) = 110;

                optCostLbl.Visible   = 'on';
                optCostField.Visible = 'on';

                try, uistack(calculateButton,'top'); catch, end
                try, uistack(optCostLbl,'top');     catch, end
                try, uistack(optCostField,'top');   catch, end
            catch
                % ignore
            end

        innerPad = 10;
        tableY   = innerPad;
        tableH   = min(120, qH - 155);   
        tableH   = max(105, tableH);

        dssTable.Units = 'normalized';
        try
            qstsStatusLbl.Units = 'normalized';
            qstsStatusLbl.Position = [0.03 0.58 0.94 0.08];
            uistack(qstsStatusLbl,'top');
        catch
        end
        dssTable.Position = [0.03 0.05 0.94 0.50];
        
        try, dssTable.Visible = 'on'; catch, end
try
            dssTable.ColumnWidth = {'auto','auto'};
        catch
        end

try
    tableTop = tableY + tableH; 
    row1Y = qH - 12;   
    row2Y = qH - 42;   

    % Row 1
    dssSystemLbl.Position(2) = row1Y;
    dssSystemDD.Position(2)  = row1Y;
    dssBusLbl.Position(2)    = row1Y;
    dssBusDD.Position(2)     = row1Y;

    % Row 2
    dssTimeLbl.Position(2)   = row2Y;
    dssTimeField.Position(2) = row2Y;
    dssRunBtn.Position(2)    = row2Y;

    try, uistack(dssTable,'bottom'); catch, end
    try, uistack(dssSystemLbl,'top'); catch, end
    try, uistack(dssSystemDD,'top'); catch, end
    try, uistack(dssBusLbl,'top'); catch, end
    try, uistack(dssBusDD,'top'); catch, end
    try, uistack(dssTimeLbl,'top'); catch, end
    try, uistack(dssTimeField,'top'); catch, end
    try, uistack(dssRunBtn,'top'); catch, end
catch
    % ignore
end

        dssPanel.Visible = 'on';

        plotPanelTop.Units = 'normalized';
        plotPanelBot.Units = 'normalized';

        rightStartPx = dssPanel.Position(1) + dssPanel.Position(3) + 0;  
        rightStartN  = min(max(rightStartPx / W, 0.05), 0.999);
        rightMarginN = -0.04; 

        plotW = max(0.18, 1 - rightStartN - rightMarginN);
        plotPanelTop.Position = [rightStartN, 0.64, plotW, 0.31];
        plotPanelBot.Position = [rightStartN, 0.24, plotW, 0.31];

        
        
        try, renderBoth(); catch, end
try, plotPanelTop.Visible='on'; uistack(plotPanelTop,'top'); catch, end
        try, plotPanelBot.Visible='on'; uistack(plotPanelBot,'top'); catch, end
        plotSelectorTop.Position   = getPlotSelectorPos(fig, plotPanelTop.Position);
        plotViewLabelTop.Position  = getPlotLabelPos(fig, plotPanelTop.Position);
        plotSelectorBot.Position   = getPlotSelectorPos(fig, plotPanelBot.Position);
        plotViewLabelBot.Position  = getPlotLabelPos(fig, plotPanelBot.Position);

        try
            dssSystemLbl.Units  = 'normalized';
            dssSystemDD.Units   = 'normalized';
            dssBusLbl.Units     = 'normalized';
            dssBusDD.Units      = 'normalized';
            dssTimeLbl.Units    = 'normalized';
            dssTimeField.Units  = 'normalized';
            dssRunBtn.Units     = 'normalized';

            y1 = 0.60;
            y2 = 0.15;

            dssSystemLbl.Position = [0.03 y1 0.25 0.10];
            dssSystemDD.Position  = [0.28 y1 0.22 0.12];
            dssBusLbl.Position    = [0.52 y1 0.18 0.10];
            dssBusDD.Position     = [0.70 y1 0.27 0.12];

            dssTimeLbl.Position   = [0.03 y2 0.10 0.10];
            dssTimeField.Position = [0.13 y2 0.15 0.12];
            dssRunBtn.Position    = [0.30 y2 0.20 0.12];

            dssSystemLbl.Visible = 'on';
            dssSystemDD.Visible  = 'on';
            dssBusLbl.Visible    = 'on';
            dssBusDD.Visible     = 'on';
            dssTimeLbl.Visible   = 'on';
            dssTimeField.Visible = 'on';
            dssRunBtn.Visible    = 'on';

            try, uistack(dssTable,'bottom'); catch, end
            try, uistack(dssSystemLbl,'top'); catch, end
            try, uistack(dssSystemDD,'top'); catch, end
            try, uistack(dssBusLbl,'top'); catch, end
            try, uistack(dssBusDD,'top'); catch, end
            try, uistack(dssTimeLbl,'top'); catch, end
            try, uistack(dssTimeField,'top'); catch, end
            try, uistack(dssRunBtn,'top'); catch, end
        catch
            % ignore
        end

    catch
        % ignore resize issues
    end
end

function drawPlaceholder(panel, msg)
    try
        delete(panel.Children);
    catch
    end
    try
        ax = uiaxes(panel);
        ax.Units = 'normalized';
        ax.Position = [0.04 0.08 0.92 0.84];
        ax.XTick = []; ax.YTick = [];
        ax.Box = 'on';
        text(ax,0.5,0.5,msg,'HorizontalAlignment','center','FontSize',11);
    catch
        % fallback: do nothing
    end
end

function renderBoth()
    if ~isappdata(fig,'lastResults')
        drawPlaceholder(plotPanelTop, 'Run Optimization to display results');
        drawPlaceholder(plotPanelBot, 'Run OpenDSS validation to display QSTS results');
        return;
    end
    R = getappdata(fig,'lastResults');
    if isempty(R)
        drawPlaceholder(plotPanelTop, 'Run Optimization to display results');
        drawPlaceholder(plotPanelBot, 'Run OpenDSS validation to display QSTS results');
        return;
    end

    try
        delete(findall(fig,'Type','legend'));
    catch
    end

    % Clear panels
    try
        delete(plotPanelTop.Children);
    catch
    end
    try
        delete(plotPanelBot.Children);
    catch
    end

    % Render each panel
    renderPanel(plotPanelTop, plotSelectorTop.Value);
    renderPanel(plotPanelBot, plotSelectorBot.Value);
end

function renderPanel(parentPanel, sel)
    R = getappdata(fig,'lastResults');
    if isempty(R)
        try
            delete(parentPanel.Children);
        catch
        end
        return;
    end
    if strcmp(sel,'All')
        g = uigridlayout(parentPanel, [2,4]);
        g.RowHeight = {'1x','1x'};
        g.ColumnWidth = {'1x','1x','1x','1x'};
        views = {'Power balance: AC side','Power balance: DC side','SOC: BESS','SOC: EVs', ...
                 'Load Curtailment','Renewables Curtailment','DR: AC load shifting','DR: DC load shifting'};
        for ii = 1:numel(views)
            ax = uiaxes(g);
            ax.Layout.Row = ceil(ii/4);
            ax.Layout.Column = mod(ii-1,4)+1;
            styleAxes(ax);
            plotOne(ax, views{ii}, R, false);
        end

    else
        ax = uiaxes(parentPanel);
        ax.Units = 'normalized';
        ax.Position = [0.02 0.08 0.96 0.88]; 
        styleAxes(ax);
        plotOne(ax, sel, R, true);
    end
end

function styleAxes(ax)
    ax.ActivePositionProperty = 'position';
    ax.TickDir = 'out';
    ax.Box = 'off';
    ax.FontSize = 11;
    ax.Position = [0.02 0.08 0.96 0.88]; 
    grid(ax,'on');
    try
        xlabel(ax,'Time step');
    catch
    end
    try
        xlabel(ax,'Time step');
    catch
    end

end

function cols = getStandaloneColors()
    cols = struct();
    cols.pv   = [0.0000 0.4470 0.7410];
    cols.wt   = [0.8500 0.3250 0.0980];
    cols.bess = [0.4660 0.6740 0.1880];
    cols.ev   = [0.4940 0.1840 0.5560];
    cols.conv = [0.3010 0.7450 0.9330];
    cols.grid = [0.3500 0.3500 0.3500];
    cols.mt   = [0.6350 0.0780 0.1840];
    cols.load = [0.1000 0.1000 0.1000];
    cols.orig = [0.4500 0.4500 0.4500];
    cols.adj  = [0.0000 0.4470 0.7410];
    cols.shift= [0.8500 0.3250 0.0980];
    cols.ac1  = [0.0000 0.4470 0.7410];
    cols.dc1  = [0.8500 0.3250 0.0980];
    cols.ac2  = [0.4660 0.6740 0.1880];
    cols.dc2  = [0.4940 0.1840 0.5560];
    cols.loss = [0.6500 0.6500 0.6500];
    cols.line = [0.9290 0.6940 0.1250];
    cols.trx  = [0.4940 0.1840 0.5560];
    cols.base = [0.4000 0.4000 0.4000];
    cols.rob  = [0.8500 0.3250 0.0980];
end

function plotStandaloneResultFigures(R, includeQSTS)
    if isempty(R) || ~isstruct(R)
        return;
    end

    cols = struct();
    cols.pv   = [0.0000 0.4470 0.7410];
    cols.wt   = [0.3010 0.7450 0.9330];
    cols.bess = [0.4660 0.6740 0.1880];
    cols.ev   = [0.8500 0.3250 0.0980];
    cols.conv = [0.4940 0.1840 0.5560];
    cols.grid = [0.3500 0.3500 0.3500];
    cols.mt   = [0.6350 0.0780 0.1840];
    cols.load = [0.1000 0.1000 0.1000];
    cols.orig = [0.4500 0.4500 0.4500];
    cols.adj  = [0.0000 0.4470 0.7410];
    cols.shift= [0.8500 0.3250 0.0980];
    cols.ac1  = [0.0000 0.4470 0.7410];
    cols.dc1  = [0.8500 0.3250 0.0980];
    cols.ac2  = [0.4660 0.6740 0.1880];
    cols.dc2  = [0.4940 0.1840 0.5560];
    cols.loss = [0.6500 0.6500 0.6500];
    cols.line = [0.9290 0.6940 0.1250];
    cols.trx  = [0.4940 0.1840 0.5560];
    cols.base = [0.4000 0.4000 0.4000];
    cols.rob  = [0.8500 0.3250 0.0980];

    if nargin < 2 || isempty(includeQSTS)
        includeQSTS = false;
    end

    % -------- Figure 1: AC/DC power balance + exchanges --------
    f1 = figure('Name','EMS Power Balance','NumberTitle','off','Color','w');
    ax1 = subplot(3,1,1,'Parent',f1); hold(ax1,'on');
    plotStandalonePowerBalance(ax1, R, 'AC', cols);
    title(ax1,'AC side power balance','FontWeight','bold');

    ax2 = subplot(3,1,2,'Parent',f1); hold(ax2,'on');
    plotStandalonePowerBalance(ax2, R, 'DC', cols);
    title(ax2,'DC side power balance','FontWeight','bold');

    axEx = subplot(3,1,3,'Parent',f1); hold(axEx,'on');
    plotStandaloneExchange(axEx, R, cols);
    title(axEx,'Grid and ILC exchange','FontWeight','bold');

    % -------- Figure 2: AC/DC DR --------
    f2 = figure('Name','EMS DR Plots','NumberTitle','off','Color','w');
    ax3 = subplot(2,1,1,'Parent',f2); hold(ax3,'on');
    plotStandaloneDR(ax3, R, 'AC', cols);
    title(ax3,'AC side demand response','FontWeight','bold');

    ax4 = subplot(2,1,2,'Parent',f2); hold(ax4,'on');
    plotStandaloneDR(ax4, R, 'DC', cols);
    title(ax4,'DC side demand response','FontWeight','bold');

    % -------- Figure 3: BESS and EV SOC --------
    f3 = figure('Name','EMS SOC Plots','NumberTitle','off','Color','w');
    ax5 = subplot(2,1,1,'Parent',f3); hold(ax5,'on');
    plotStandaloneBESSSOC(ax5, R, cols);
    title(ax5,'BESS SOC','FontWeight','bold');

    ax6 = subplot(2,1,2,'Parent',f3); hold(ax6,'on');
    plotStandaloneEVSOC(ax6, R, cols);
    title(ax6,'EV SOC','FontWeight','bold');

    % -------- Figure 4: Curtailment --------
    f4 = figure('Name','EMS Curtailment','NumberTitle','off','Color','w');
    ax7 = subplot(2,1,1,'Parent',f4); hold(ax7,'on');
    plotStandaloneLoadCurtailment(ax7, R, cols);
    title(ax7,'Load curtailment','FontWeight','bold');

    ax8 = subplot(2,1,2,'Parent',f4); hold(ax8,'on');
    plotStandaloneRenewableCurtailment(ax8, R, cols);
    title(ax8,'Renewable curtailment','FontWeight','bold');

    % -------- Figure 5: Stochastic scenarios --------
    f5 = figure('Name','EMS Uncertainty Scenarios','NumberTitle','off','Color','w');
    ax9  = subplot(3,2,1,'Parent',f5); plotStandaloneScenario(ax9,  R, 'PV',   'AC'); title(ax9, 'PV scenarios (AC)','FontWeight','bold');
    ax10 = subplot(3,2,2,'Parent',f5); plotStandaloneScenario(ax10, R, 'PV',   'DC'); title(ax10,'PV scenarios (DC)','FontWeight','bold');
    ax11 = subplot(3,2,3,'Parent',f5); plotStandaloneScenario(ax11, R, 'WT',   'AC'); title(ax11,'WT scenarios (AC)','FontWeight','bold');
    ax12 = subplot(3,2,4,'Parent',f5); plotStandaloneScenario(ax12, R, 'WT',   'DC'); title(ax12,'WT scenarios (DC)','FontWeight','bold');
    ax13 = subplot(3,2,5,'Parent',f5); plotStandaloneScenario(ax13, R, 'LOAD', 'AC'); title(ax13,'Load scenarios (AC)','FontWeight','bold');
    ax14 = subplot(3,2,6,'Parent',f5); plotStandaloneScenario(ax14, R, 'LOAD', 'DC'); title(ax14,'Load scenarios (DC)','FontWeight','bold');

    % -------- Figure 6: Robust uncertainty --------
    f6 = figure('Name','EMS Robust Uncertainty','NumberTitle','off','Color','w');
    ax15 = subplot(3,2,1,'Parent',f6); plotStandaloneRobust(ax15, R, 'PV',   'AC', cols); title(ax15,'PV robust (AC)','FontWeight','bold');
    ax16 = subplot(3,2,2,'Parent',f6); plotStandaloneRobust(ax16, R, 'PV',   'DC', cols); title(ax16,'PV robust (DC)','FontWeight','bold');
    ax17 = subplot(3,2,3,'Parent',f6); plotStandaloneRobust(ax17, R, 'WT',   'AC', cols); title(ax17,'WT robust (AC)','FontWeight','bold');
    ax18 = subplot(3,2,4,'Parent',f6); plotStandaloneRobust(ax18, R, 'WT',   'DC', cols); title(ax18,'WT robust (DC)','FontWeight','bold');
    ax19 = subplot(3,2,5,'Parent',f6); plotStandaloneRobust(ax19, R, 'LOAD', 'AC', cols); title(ax19,'Load robust (AC)','FontWeight','bold');
    ax20 = subplot(3,2,6,'Parent',f6); plotStandaloneRobust(ax20, R, 'LOAD', 'DC', cols); title(ax20,'Load robust (DC)','FontWeight','bold');

    % -------- Figure 7: QSTS analysis --------
    if includeQSTS
        plotStandaloneQSTSFigure(R, cols);
    end
end

function plotStandaloneQSTSFigure(R, cols)
    f7 = figure('Name','EMS QSTS Analysis','NumberTitle','off','Color','w');
    plotStandaloneQSTS(f7, R, cols);
end

function plotStandalonePowerBalance(ax, R, side, cols)
    T = 96;
    if isfield(R,'Num_var') && isnumeric(R.Num_var) && isscalar(R.Num_var) && R.Num_var > 0
        T = min(96, R.Num_var);
    end
    ensureColT = @(v) localEnsureColT(v, T);

    switch upper(string(side))
        case "AC"
            windSt = ensureColT(getFieldOrDefaultRaw(R,'Wind_AC_status',1));
            pv  = ensureColT(getFieldOrDefaultRaw(R,'P_PV1',0)) - ensureColT(getFieldOrDefaultRaw(R,'P_Cur_PV1',0));
            wt  = windSt .* ensureColT(getFieldOrDefaultRaw(R,'P_WT1',0)) - ensureColT(getFieldOrDefaultRaw(R,'P_Cur_WT1',0));
            bess = ensureColT(getFieldOrDefaultRaw(R,'P_BESS1',0));
            PEV = getFieldOrDefaultRaw(R,'P_EV_AC',[]);
            if isempty(PEV)
                ev = ensureColT(getFieldOrDefaultRaw(R,'P_EV1',0));
            elseif isvector(PEV)
                ev = ensureColT(PEV);
            else
                ev = ensureColT(sum(PEV,2));
            end
            conv = -ensureColT(getFieldOrDefaultRaw(R,'P_conv',0));
            gridp = ensureColT(getFieldOrDefaultRaw(R,'P_grid',0));
            mt = ensureColT(getFieldOrDefaultRaw(R,'P_diesel', getFieldOrDefaultRaw(R,'P_CDG_AC',0)));
            adjLoad = ensureColT(getFieldOrDefaultRaw(R,'P_CL1',0)) + ...
                      ensureColT(getFieldOrDefaultRaw(R,'P_NL1_served', getFieldOrDefaultRaw(R,'P_NL1',0)));
            labels = {'PV','WT','BESS','EV','ILC','Grid','MT','Adjusted load'};
            cmat = [cols.pv; cols.wt; cols.bess; cols.ev; cols.conv; cols.grid; cols.mt];
        otherwise
            windSt = ensureColT(getFieldOrDefaultRaw(R,'Wind_DC_status',1));
            pv  = ensureColT(getFieldOrDefaultRaw(R,'P_PV2',0)) - ensureColT(getFieldOrDefaultRaw(R,'P_Cur_PV2',0));
            wt  = windSt .* ensureColT(getFieldOrDefaultRaw(R,'P_WT2',0)) - ensureColT(getFieldOrDefaultRaw(R,'P_Cur_WT2',0));
            bess = ensureColT(getFieldOrDefaultRaw(R,'P_BESS2',0));
            PEV = getFieldOrDefaultRaw(R,'P_EV_DC',[]);
            if isempty(PEV)
                ev = ensureColT(getFieldOrDefaultRaw(R,'P_EV2',0));
            elseif isvector(PEV)
                ev = ensureColT(PEV);
            else
                ev = ensureColT(sum(PEV,2));
            end
            conv = ensureColT(getFieldOrDefaultRaw(R,'P_conv',0));
            mt = ensureColT(getFieldOrDefaultRaw(R,'P_MT2', getFieldOrDefaultRaw(R,'P_MT_DC',0)));
            gridp = [];
            adjLoad = ensureColT(getFieldOrDefaultRaw(R,'P_CL2',0)) + ...
                      ensureColT(getFieldOrDefaultRaw(R,'P_NL2_served', getFieldOrDefaultRaw(R,'P_NL2',0)));
            labels = {'PV','WT','BESS','EV','ILC','MT','Adjusted load'};
            cmat = [cols.pv; cols.wt; cols.bess; cols.ev; cols.conv; cols.mt];
    end

    data = [pv, wt, bess, ev, conv];
    if ~isempty(gridp)
        data = [data, gridp, mt];
    else
        data = [data, mt];
    end

    hBar = bar(ax, data, 'stacked', 'BarWidth', 0.82, 'FaceColor','flat');
    for k = 1:min(numel(hBar), size(cmat,1))
        hBar(k).CData = repmat(cmat(k,:), size(hBar(k).YData,1), 1);
        hBar(k).EdgeColor = 'none';
    end
    hLoad = plot(ax, adjLoad, '-', 'LineWidth', 1.8, 'Color', cols.load);
    ylabel(ax, 'Power (kW)');
    xlabel(ax, 'Time step');
    lgd = legend(ax, [hBar(:); hLoad], labels, 'Location','best');
    setStandaloneAxesStyle(ax);
    setStandaloneLegendStyle(lgd);
end


function plotStandaloneExchange(ax, R, cols)
    gridp = getFieldOrDefault(R,'P_grid',0);
    ilc   = getFieldOrDefault(R,'P_conv',0);

    p1 = plot(ax, gridp(:), '-', 'LineWidth', 1.9, 'Color', cols.grid);
    hold(ax,'on');
    p2 = plot(ax, ilc(:),   '-', 'LineWidth', 1.9, 'Color', cols.conv);
    yline(ax, 0, ':', 'LineWidth', 1.0, 'Color', cols.base);
    xlabel(ax,'Time step');
    ylabel(ax,'Power (kW)');
    lgd = legend(ax, [p1 p2], {'Grid exchange','ILC exchange'}, 'Location','best');
    setStandaloneAxesStyle(ax);
    setStandaloneLegendStyle(lgd);
end

function plotStandaloneDR(ax, R, side, cols)
    switch upper(string(side))
        case "AC"
            orig = getFieldOrDefault(R,'P_NL1',0);
            adj  = getFieldOrDefault(R,'P_NL1_served', orig);
            ttl = 'Adjusted load (AC)';
        otherwise
            orig = getFieldOrDefault(R,'P_NL2',0);
            adj  = getFieldOrDefault(R,'P_NL2_served', orig);
            ttl = 'Adjusted load (DC)';
    end
    shift = adj(:) - orig(:);
    b = bar(ax, shift, 'BarWidth', 0.82, 'FaceColor', cols.shift, 'EdgeColor','none');
    hold(ax,'on');
    p1 = plot(ax, orig(:), '-', 'LineWidth', 1.7, 'Color', cols.orig);
    p2 = plot(ax, adj(:),  '-', 'LineWidth', 1.9, 'Color', cols.adj);
    xlabel(ax, 'Time step');
    ylabel(ax, 'Power (kW)');
    lgd = legend(ax, [b p1 p2], {'Shifted amount','Original NL','Adjusted NL'}, 'Location','best');
    setStandaloneAxesStyle(ax);
    setStandaloneLegendStyle(lgd);
end

function plotStandaloneLoadCurtailment(ax, R, cols)

    ls_cl1 = getFieldOrDefault(R,'P_Shed_CL1', getFieldOrDefault(R,'P_shed1', getFieldOrDefault(R,'P_LS1',0)));
    ls_nl1 = getFieldOrDefault(R,'P_Shed_NL1', 0);
    ls_cl2 = getFieldOrDefault(R,'P_Shed_CL2', getFieldOrDefault(R,'P_shed2', getFieldOrDefault(R,'P_LS2',0)));
    ls_nl2 = getFieldOrDefault(R,'P_Shed_NL2', 0);

    hold(ax,'on');
    p1 = plot(ax, ls_cl1, '-',  'LineWidth', 1.8, 'Color', cols.ac1);
    p2 = plot(ax, ls_nl1, '--', 'LineWidth', 1.8, 'Color', cols.ac1);
    p3 = plot(ax, ls_cl2, '-',  'LineWidth', 1.8, 'Color', cols.dc1);
    p4 = plot(ax, ls_nl2, '--', 'LineWidth', 1.8, 'Color', cols.dc1);

    xlabel(ax,'Time step');
    ylabel(ax,'Power (kW)');
    lgd = legend(ax, [p1 p2 p3 p4], ...
        {'AC critical shed','AC non-critical shed','DC critical shed','DC non-critical shed'}, ...
        'Location','best');
    setStandaloneAxesStyle(ax);
    setStandaloneLegendStyle(lgd);
end

function plotStandaloneRenewableCurtailment(ax, R, cols)
    pv1 = getFieldOrDefault(R,'P_Cur_PV1',0);
    pv2 = getFieldOrDefault(R,'P_Cur_PV2',0);
    wt1 = getFieldOrDefault(R,'P_Cur_WT1',0);
    wt2 = getFieldOrDefault(R,'P_Cur_WT2',0);
    p1 = plot(ax, pv1, '-',  'LineWidth', 1.8, 'Color', cols.pv);
    hold(ax,'on');
    p2 = plot(ax, pv2, '--', 'LineWidth', 1.8, 'Color', cols.pv);
    p3 = plot(ax, wt1, '-',  'LineWidth', 1.8, 'Color', cols.wt);
    p4 = plot(ax, wt2, '--', 'LineWidth', 1.8, 'Color', cols.wt);
    xlabel(ax,'Time step'); ylabel(ax,'Power (kW)');
    lgd = legend(ax, [p1 p2 p3 p4], {'PV AC curtailment','PV DC curtailment','WT AC curtailment','WT DC curtailment'}, 'Location','best');
    setStandaloneAxesStyle(ax);
    setStandaloneLegendStyle(lgd);
end

function plotStandaloneScenario(ax, R, asset, side)
    hold(ax,'on');
    switch upper(string(asset))
        case "PV"
            if upper(string(side)) == "AC"
                hasScen = isfield(R,'PV1_scen') && ~isempty(R.PV1_scen);
                if hasScen
                    base = getFieldOrDefault(R,'P_PV1',0);
                    scen = R.PV1_scen .* getFieldOrDefaultRaw(R,'PV1_Max',1);
                    prob = getFieldOrDefaultRaw(R,'PV1_prob',[]);
                end
            else
                hasScen = isfield(R,'PV2_scen') && ~isempty(R.PV2_scen);
                if hasScen
                    base = getFieldOrDefault(R,'P_PV2',0);
                    scen = R.PV2_scen .* getFieldOrDefaultRaw(R,'PV2_Max',1);
                    prob = getFieldOrDefaultRaw(R,'PV2_prob',[]);
                end
            end
        case "WT"
            if upper(string(side)) == "AC"
                hasScen = isfield(R,'WT1_scen') && ~isempty(R.WT1_scen);
                if ~hasScen
                    try
                        tmp = evalin('base','P_WT1_scen');
                        if ~isempty(tmp)
                            R.WT1_scen = tmp;
                            try; R.WT1_prob = evalin('base','P_WT1_prob'); catch; end
                            hasScen = true;
                        end
                    catch
                    end
                end
                if hasScen
                    base = getFieldOrDefault(R,'P_WT1',0);
                    scen = R.WT1_scen .* getFieldOrDefaultRaw(R,'WT1_Max',1);
                    prob = getFieldOrDefaultRaw(R,'WT1_prob',[]);
                end
            else
                hasScen = isfield(R,'WT2_scen') && ~isempty(R.WT2_scen);
                if ~hasScen
                    try
                        tmp = evalin('base','P_WT2_scen');
                        if ~isempty(tmp)
                            R.WT2_scen = tmp;
                            try; R.WT2_prob = evalin('base','P_WT2_prob'); catch; end
                            hasScen = true;
                        end
                    catch
                    end
                end
                if hasScen
                    base = getFieldOrDefault(R,'P_WT2',0);
                    scen = R.WT2_scen .* getFieldOrDefaultRaw(R,'WT2_Max',1);
                    prob = getFieldOrDefaultRaw(R,'WT2_prob',[]);
                end
            end
        otherwise
            if upper(string(side)) == "AC"
                hasScen = isfield(R,'Load1_scen') && ~isempty(R.Load1_scen);
                if hasScen
                    base = getFieldOrDefault(R,'P_CL1',0) + getFieldOrDefault(R,'P_NL1',0);
                    scen = R.Load1_scen;
                    prob = getFieldOrDefaultRaw(R,'Load1_prob',[]);
                end
            else
                hasScen = isfield(R,'Load2_scen') && ~isempty(R.Load2_scen);
                if hasScen
                    base = getFieldOrDefault(R,'P_CL2',0) + getFieldOrDefault(R,'P_NL2',0);
                    scen = R.Load2_scen;
                    prob = getFieldOrDefaultRaw(R,'Load2_prob',[]);
                end
            end
    end
    if exist('hasScen','var') && hasScen
        plotScenarioSpaghetti(ax, base, scen, prob, '', false);
        setStandaloneAxesStyle(ax);
    else
        showNoScenario(ax, sprintf('%s (%s)', upper(char(asset)), upper(char(side))));
    end
end

function plotStandaloneRobust(ax, R, asset, side, cols)
    hold(ax,'on');
    switch upper(string(asset))
        case "PV"
            unc = getappdata(fig,'pv_unc');
            if upper(string(side)) == "AC"
                base = getFieldOrDefault(R,'P_PV1',0);
                used = getFieldOrDefault(R,'P_PV1_eff',base);
                cur = unc.AC;
                c1 = cols.pv;
            else
                base = getFieldOrDefault(R,'P_PV2',0);
                used = getFieldOrDefault(R,'P_PV2_eff',base);
                cur = unc.DC;
                c1 = cols.pv;
            end
            isLoad = false;
        case "WT"
            unc = getappdata(fig,'wt_unc');
            if upper(string(side)) == "AC"
                base = getFieldOrDefault(R,'P_WT1',0);
                used = getFieldOrDefault(R,'P_WT1_eff',base);
                cur = unc.AC;
                c1 = cols.wt;
            else
                base = getFieldOrDefault(R,'P_WT2',0);
                used = getFieldOrDefault(R,'P_WT2_eff',base);
                cur = unc.DC;
                c1 = cols.wt;
            end
            isLoad = false;
        otherwise
            unc = getappdata(fig,'load_unc');
            if upper(string(side)) == "AC"
                base = getFieldOrDefault(R,'P_CL1',0) + getFieldOrDefault(R,'P_NL1',0);
                used = getFieldOrDefault(R,'P_Load1_eff',base);
                cur = unc.AC;
            else
                base = getFieldOrDefault(R,'P_CL2',0) + getFieldOrDefault(R,'P_NL2',0);
                used = getFieldOrDefault(R,'P_Load2_eff',base);
                cur = unc.DC;
            end
            c1 = cols.load;
            isLoad = true;
    end
    isRob = isstruct(cur) && isfield(cur,'mode') && any(strcmpi(string(cur.mode), ["Robust"]));
    p1 = plot(ax, base, '-', 'LineWidth', 1.2, 'Color', cols.base);
    if isRob
        [rob, ~] = budgetRobustProfile(base, cur, isLoad);
        p2 = plot(ax, rob, '-', 'LineWidth', 2.0, 'Color', cols.rob);
        labels = {'Base','Robust'};
    else
        p2 = plot(ax, used, '-', 'LineWidth', 2.0, 'Color', c1);
        labels = {'Base','Used'};
    end
    xlabel(ax,'Time step'); ylabel(ax,'Power (kW)');
    lgd = legend(ax, [p1 p2], labels, 'Location','best');
    setStandaloneAxesStyle(ax);
    setStandaloneLegendStyle(lgd);
end

function plotStandaloneQSTS(fh, R, cols)
    if ~(isfield(R,'OpenDSS') && ~isempty(R.OpenDSS))
        ax = subplot(1,1,1,'Parent',fh);
        text(ax,0.1,0.5,'No QSTS results. Run OpenDSS validation first.');
        axis(ax,'off');
        return;
    end
    OD = R.OpenDSS;
    tShow = 1;
    try
        tShow = max(1, round(dssTimeField.Value));
    catch
        if isfield(OD,'BusVpu') && ~isempty(OD.BusVpu)
            tShow = min(size(OD.BusVpu,2), 1);
        end
    end

    ax1 = subplot(3,2,1,'Parent',fh); hold(ax1,'on');
    if isfield(OD,'Vmin_pu') && isfield(OD,'Vmax_pu')
        t = (1:numel(OD.Vmin_pu)).';
        p1 = plot(ax1, t, OD.Vmin_pu, '-', 'LineWidth', 1.7, 'Color', cols.ac1);
        p2 = plot(ax1, t, OD.Vmax_pu, '-', 'LineWidth', 1.7, 'Color', cols.dc1);
        lgd = legend(ax1, [p1 p2], {'Vmin','Vmax'}, 'Location','best'); setStandaloneLegendStyle(lgd);
        xlabel(ax1,'Time step'); ylabel(ax1,'Voltage (pu)');
        setStandaloneAxesStyle(ax1);
    else, showNoScenario(ax1,'QSTS voltage min/max'); end
    title(ax1,'Voltage min/max','FontWeight','bold');

    ax2 = subplot(3,2,2,'Parent',fh); hold(ax2,'on');
    if isfield(OD,'Loss_kW')
        plot(ax2, (1:numel(OD.Loss_kW)).', OD.Loss_kW, '-', 'LineWidth', 1.8, 'Color', cols.loss);
        xlabel(ax2,'Time step'); ylabel(ax2,'Losses (kW)'); setStandaloneAxesStyle(ax2);
    else, showNoScenario(ax2,'QSTS losses'); end
    title(ax2,'Losses','FontWeight','bold');

    ax3 = subplot(3,2,3,'Parent',fh); hold(ax3,'on');
    if isfield(OD,'MaxLineLoading_pct')
        plot(ax3, (1:numel(OD.MaxLineLoading_pct)).', OD.MaxLineLoading_pct, '-', 'LineWidth', 1.8, 'Color', cols.line);
        xlabel(ax3,'Time step'); ylabel(ax3,'Loading (%)'); setStandaloneAxesStyle(ax3);
    else, showNoScenario(ax3,'QSTS line loading'); end
    title(ax3,'Max line loading (%)','FontWeight','bold');

    ax4 = subplot(3,2,4,'Parent',fh); hold(ax4,'on');
    if isfield(OD,'MaxTrxLoading_pct')
        plot(ax4, (1:numel(OD.MaxTrxLoading_pct)).', OD.MaxTrxLoading_pct, '-', 'LineWidth', 1.8, 'Color', cols.trx);
        xlabel(ax4,'Time step'); ylabel(ax4,'Loading (%)'); setStandaloneAxesStyle(ax4);
    else, showNoScenario(ax4,'QSTS transformer loading'); end
    title(ax4,'Max transformer loading','FontWeight','bold');

    ax5 = subplot(3,2,5,'Parent',fh); hold(ax5,'on');
    if isfield(OD,'BusVpu') && ~isempty(OD.BusVpu)
        tShow = max(1, min(size(OD.BusVpu,2), tShow));
        plot(ax5, OD.BusVpu(:,tShow), '-', 'LineWidth', 1.5, 'Color', cols.ac2);
        xlabel(ax5,'Bus index'); ylabel(ax5,'Voltage (pu)'); setStandaloneAxesStyle(ax5);
    else, showNoScenario(ax5,'QSTS bus voltages'); end
    title(ax5, sprintf('Bus voltages (t=%d)', tShow), 'FontWeight','bold');

    ax6 = subplot(3,2,6,'Parent',fh); hold(ax6,'on');
    if isfield(OD,'NodeVpu') && ~isempty(OD.NodeVpu)
        tShow2 = max(1, min(size(OD.NodeVpu,2), tShow));
        plot(ax6, OD.NodeVpu(:,tShow2), '-', 'LineWidth', 1.5, 'Color', cols.dc2);
        xlabel(ax6,'Node index'); ylabel(ax6,'Voltage (pu)'); setStandaloneAxesStyle(ax6);
    else, showNoScenario(ax6,'QSTS node voltages'); end
    title(ax6, sprintf('Node voltages (t=%d)', tShow), 'FontWeight','bold');
end

function plotStandaloneBESSSOC(ax, R, cols)
    s1 = getFieldOrDefault(R,'SOC1',0);
    s2 = getFieldOrDefault(R,'SOC2',0);
    plot(ax, s1, '-', 'LineWidth', 1.9, 'Color', cols.ac1);
    hold(ax,'on');
    plot(ax, s2, '-', 'LineWidth', 1.9, 'Color', cols.dc1);
    xlabel(ax, 'Time step');
    ylabel(ax, 'SOC (%)');
    ylim(ax,[0 100]);
    lgd = legend(ax, {'BESS AC','BESS DC'}, 'Location','best');
    setStandaloneAxesStyle(ax);
    setStandaloneLegendStyle(lgd);
end

function plotStandaloneEVSOC(ax, R, cols)
    nT = 96;
    EVAC = normalizeSOCSeries(getFieldOrDefaultRaw(R,'EV_AC_SOC',[]), nT, getFieldOrDefaultRaw(R,'NEV_AC',[]), ...
                              getFieldOrDefault(R,'EV1SOC', getFieldOrDefault(R,'EV_SOC',0)));
    EVDC = normalizeSOCSeries(getFieldOrDefaultRaw(R,'EV_DC_SOC',[]), nT, getFieldOrDefaultRaw(R,'NEV_DC',[]), ...
                              getFieldOrDefault(R,'EV2SOC',0));

    labels = {};
    for k = 1:size(EVAC,2)
        plot(ax, EVAC(:,k), '-', 'LineWidth', 1.8);
        labels{end+1} = sprintf('EV AC %d',k); 
    end
    for k = 1:size(EVDC,2)
        plot(ax, EVDC(:,k), '--', 'LineWidth', 1.8);
        labels{end+1} = sprintf('EV DC %d',k); 
    end
    xlabel(ax, 'Time step');
    ylabel(ax, 'SOC (%)');
    ylim(ax,[0 100]);
    lgd = legend(ax, labels, 'Location','best');
    setStandaloneAxesStyle(ax);
    setStandaloneLegendStyle(lgd);
end

function M = normalizeSOCSeries(S, nT, nSeriesHint, fallback)
    if nargin < 2 || isempty(nT)
        nT = 96;
    end
    if nargin < 3 || isempty(nSeriesHint) || ~isscalar(nSeriesHint) || nSeriesHint <= 0
        nSeriesHint = 1;
    end
    if isempty(S)
        M = localEnsureColT(fallback, nT);
        return;
    end

    if isvector(S)
        S = S(:);
        if numel(S) == nT * nSeriesHint
            M = reshape(S, [nT, nSeriesHint]);
        else
            M = localEnsureColT(S, nT);
        end
        return;
    end

    if size(S,1) ~= nT && size(S,2) == nT
        S = S.';
    end
    if size(S,1) ~= nT && numel(S) == nT * nSeriesHint
        S = reshape(S, [nT, nSeriesHint]);
    end
    if size(S,1) ~= nT
        tmp = zeros(nT, size(S,2));
        for k = 1:size(S,2)
            tmp(:,k) = localEnsureColT(S(:,k), nT);
        end
        S = tmp;
    end
    M = S;
end

function setStandaloneAxesStyle(ax)
    if isempty(ax) || ~isgraphics(ax)
        return;
    end
    ax.Box = 'off';
    ax.TickDir = 'out';
    ax.LineWidth = 0.9;
    ax.FontSize = 11;
    grid(ax,'on');
end

function setStandaloneLegendStyle(lgd)
    if isempty(lgd) || ~isvalid(lgd)
        return;
    end
    lgd.Box = 'off';
    lgd.AutoUpdate = 'off';
    lgd.FontSize = 9;
    if isprop(lgd,'Interpreter')
        lgd.Interpreter = 'none';
    end
end

function v = getFieldOrDefault(S, fname, defaultVal)
    if isfield(S, fname)
        v = S.(fname);
    else
        v = defaultVal;
    end

    try
        if isnumeric(v) || islogical(v)
            if isscalar(v)
                v = v .* ones(Num_var,1);
            else
                v = v(:);
            end
        end
    catch
    end
end

function v = getFieldOrDefaultRaw(S, fname, defaultVal)
    if isempty(S) || ~isstruct(S) || ~isfield(S, fname)
        v = defaultVal;
    else
        v = S.(fname);
    end
end

function v = localEnsureColT(v, T)
    if nargin < 2 || isempty(T) || T <= 0
        T = 1;
    end
    if isempty(v)
        v = 0;
    end
    if ~(isnumeric(v) || islogical(v))
        v = zeros(T,1);
        return;
    end
    if isscalar(v)
        v = double(v) .* ones(T,1);
    else
        v = v(:);
        if numel(v) < T
            v(end+1:T,1) = 0;
        elseif numel(v) > T
            v = v(1:T);
        end
    end
end

function x = getNumericScalar(v, defaultVal)
    try
        if isobject(v) && isprop(v,'Value')
            v = v.Value;
        end
    catch
    end
    if nargin < 2 || isempty(defaultVal)
        defaultVal = 0;
    end
    if isempty(v) || ~isnumeric(v)
        x = defaultVal;
    else
        x = double(v(1));
    end
end

function plotOne(ax, sel, R, withLegend)
    cla(ax); hold(ax,'on');

    switch sel
        case 'Power balance: AC side'
            T = 96;
            if isfield(R,'Num_var') && isnumeric(R.Num_var) && isscalar(R.Num_var) && R.Num_var>0
                T = min(96, R.Num_var);
            end
            ensureColT = @(v) localEnsureColT(v, T);

            windAC = ensureColT(getFieldOrDefaultRaw(R,'Wind_AC_status',1));
            pv1 = ensureColT(getFieldOrDefaultRaw(R,'P_PV1',0)) - ensureColT(getFieldOrDefaultRaw(R,'P_Cur_PV1',0));
            wt1 = windAC .* ensureColT(getFieldOrDefaultRaw(R,'P_WT1',0)) - ensureColT(getFieldOrDefaultRaw(R,'P_Cur_WT1',0));
            bess1 = ensureColT(getFieldOrDefaultRaw(R,'P_BESS1',0));
            PEV = getFieldOrDefaultRaw(R,'P_EV_AC',[]);
            if isempty(PEV)
                ev1 = ensureColT(getFieldOrDefaultRaw(R,'P_EV1',0));
            elseif isvector(PEV)
                ev1 = ensureColT(PEV);
            else
                ev1 = ensureColT(sum(PEV,2));
            end
            convAC = -ensureColT(getFieldOrDefaultRaw(R,'P_conv',0));
            gridAC = ensureColT(getFieldOrDefaultRaw(R,'P_grid',0));
            mtAC = ensureColT(getFieldOrDefaultRaw(R,'P_diesel', getFieldOrDefaultRaw(R,'P_CDG_AC',0)));
            adjLoadAC = ensureColT(getFieldOrDefaultRaw(R,'P_CL1',0)) + ...
                        ensureColT(getFieldOrDefaultRaw(R,'P_NL1_served', getFieldOrDefaultRaw(R,'P_NL1',0)));

            data = [pv1, wt1, bess1, ev1, convAC, gridAC, mtAC];
            hBar = bar(ax, data, 'stacked', 'FaceColor','flat');
            colors = lines(7);
            for kk = 1:min(numel(hBar), size(colors,1))
                hBar(kk).CData = repmat(colors(kk,:), size(hBar(kk).YData,1), 1);
            end
            hLoad = plot(ax, adjLoadAC, 'k.','MarkerSize',12);
            ylabel(ax, 'Power (kW)');
            xlabel(ax, 'Time step');
            if withLegend
                lgd = legend(ax, [hBar(:); hLoad], {'PV','WT','BESS','EV','ILC','Grid','MT','Adj load'});
                applyLegendStyle(lgd);
            end

        case 'Power balance: DC side'
            T = 96;
            if isfield(R,'Num_var') && isnumeric(R.Num_var) && isscalar(R.Num_var) && R.Num_var>0
                T = min(96, R.Num_var);
            end
            ensureColT = @(v) localEnsureColT(v, T);

            windDC = ensureColT(getFieldOrDefaultRaw(R,'Wind_DC_status',1));
            pv2 = ensureColT(getFieldOrDefaultRaw(R,'P_PV2',0)) - ensureColT(getFieldOrDefaultRaw(R,'P_Cur_PV2',0));
            wt2 = windDC .* ensureColT(getFieldOrDefaultRaw(R,'P_WT2',0)) - ensureColT(getFieldOrDefaultRaw(R,'P_Cur_WT2',0));
            bess2 = ensureColT(getFieldOrDefaultRaw(R,'P_BESS2',0));
            PEVdc = getFieldOrDefaultRaw(R,'P_EV_DC',[]);
            if isempty(PEVdc)
                ev2 = ensureColT(getFieldOrDefaultRaw(R,'P_EV2',0));
            elseif isvector(PEVdc)
                ev2 = ensureColT(PEVdc);
            else
                ev2 = ensureColT(sum(PEVdc,2));
            end
            convDC = ensureColT(getFieldOrDefaultRaw(R,'P_conv',0));
            mtDC = ensureColT(getFieldOrDefaultRaw(R,'P_MT2', getFieldOrDefaultRaw(R,'P_MT_DC',0)));
            adjLoadDC = ensureColT(getFieldOrDefaultRaw(R,'P_CL2',0)) + ...
                        ensureColT(getFieldOrDefaultRaw(R,'P_NL2_served', getFieldOrDefaultRaw(R,'P_NL2',0)));

            data = [pv2, wt2, bess2, ev2, convDC, mtDC];
            hBar2 = bar(ax, data, 'stacked', 'FaceColor','flat');
            colors = lines(7);
            for kk = 1:min(numel(hBar2), size(colors,1))
                hBar2(kk).CData = repmat(colors(kk,:), size(hBar2(kk).YData,1), 1);
            end
            hLoad2 = plot(ax, adjLoadDC, 'k.','MarkerSize',12);
            ylabel(ax, 'Power (kW)');
            xlabel(ax, 'Time step');
            if withLegend
                lgd = legend(ax, [hBar2(:); hLoad2], {'PV','WT','BESS','EV','ILC','MT','Adj load'});
                applyLegendStyle(lgd);
            end

        case 'SOC: BESS'
            plot(ax, getFieldOrDefault(R,'SOC1',0));
            plot(ax, getFieldOrDefault(R,'SOC2',0));
            ylabel(ax, 'SOC (%)');
            xlabel(ax, 'Time step');
            try
                ylim(ax,[0,130]);
            catch
            end

            if withLegend
                lgd = legend(ax, {'BESS_1','BESS_2'});
                applyLegendStyle(lgd);
            end

        case 'SOC: EVs'
            % Plot each EV SOC independently over the scheduling horizon 
            nT = 96;  
            t = (1:nT)';

            EVAC = getFieldOrDefaultRaw(R,'EV_AC_SOC',[]);
            nev  = getFieldOrDefaultRaw(R,'NEV_AC',[]);
            if isempty(nev) || ~isscalar(nev) || nev<=0
                if isnumeric(EVAC) && ~isempty(EVAC)
                    if ismatrix(EVAC) && ~isvector(EVAC)
                        nev = size(EVAC,2);
                    else
                        nev = 1;
                    end
                else
                    nev = 1;
                end
            end

            labels = {};
            if isempty(EVAC)
                y = getFieldOrDefault(R,'EV1SOC',getFieldOrDefault(R,'EV_SOC',0));
                y = localEnsureColT(y, nT);
                plot(ax, t, y);
                labels = {'EV_AC_1'};
            else
                if isvector(EVAC)
                    EVAC = EVAC(:);
                    if numel(EVAC) == nT*nev
                        EVAC = reshape(EVAC, [nT, nev]);
                    else
                        EVAC = localEnsureColT(EVAC, nT);
                        nev = 1;
                    end
                else
                    if size(EVAC,1) ~= nT && size(EVAC,2) == nT
                        EVAC = EVAC.'; 
                    end
                    if size(EVAC,1) ~= nT && numel(EVAC) == nT*nev
                        EVAC = reshape(EVAC, [nT, nev]);
                    end
                    if size(EVAC,1) ~= nT
                        tmp = zeros(nT, size(EVAC,2));
                        for kk = 1:size(EVAC,2)
                            tmp(:,kk) = localEnsureColT(EVAC(:,kk), nT);
                        end
                        EVAC = tmp;
                    end
                    nev = size(EVAC,2);
                end

                for k = 1:nev
                    plot(ax, t, EVAC(:,k));
                end
                labels = arrayfun(@(k) sprintf('EV_AC_%d', k), 1:nev, 'UniformOutput', false);
            end

            
            % ---- DC EV SOCs (fleet) ----
            EVDC = getFieldOrDefaultRaw(R,'EV_DC_SOC',[]);
            nev2 = getFieldOrDefaultRaw(R,'NEV_DC',[]);
            if isempty(nev2) || ~isscalar(nev2) || nev2<=0
                if isnumeric(EVDC) && ~isempty(EVDC)
                    if ismatrix(EVDC) && ~isvector(EVDC)
                        nev2 = size(EVDC,2);
                    else
                        nev2 = 1;
                    end
                else
                    nev2 = 1;
                end
            end

            if isempty(EVDC)
                y2 = getFieldOrDefault(R,'EV2SOC',0);
                y2 = localEnsureColT(y2, nT);
                plot(ax, t, y2);
                labels = [labels, {'EV_DC_1'}];
            else
                if isvector(EVDC)
                    EVDC = EVDC(:);
                    if numel(EVDC) == nT*nev2
                        EVDC = reshape(EVDC, [nT, nev2]);
                    else
                        EVDC = localEnsureColT(EVDC, nT);
                        nev2 = 1;
                    end
                else
                    if size(EVDC,1) ~= nT && size(EVDC,2) == nT
                        EVDC = EVDC.';
                    end
                    if size(EVDC,1) ~= nT && numel(EVDC) == nT*nev2
                        EVDC = reshape(EVDC, [nT, nev2]);
                    end
                    if size(EVDC,1) ~= nT
                        tmp2 = zeros(nT, size(EVDC,2));
                        for kk = 1:size(EVDC,2)
                            tmp2(:,kk) = localEnsureColT(EVDC(:,kk), nT);
                        end
                        EVDC = tmp2;
                    end
                    nev2 = size(EVDC,2);
                end

                for k = 1:nev2
                    plot(ax, t, EVDC(:,k));
                end
                labels = [labels, arrayfun(@(k) sprintf('EV_DC_%d', k), 1:nev2, 'UniformOutput', false)];
            end

ylabel(ax, 'SOC (%)');
            xlabel(ax, 'Time step');

            if withLegend
                lgd = legend(ax, labels, 'Location','best');
                applyLegendStyle(lgd);
            end

case 'Load Curtailment'
            plot(ax, getFieldOrDefault(R,'P_Shed_CL1',0));
            plot(ax, getFieldOrDefault(R,'P_Shed_NL1',0));
            plot(ax, getFieldOrDefault(R,'P_Shed_CL2',0));
            plot(ax, getFieldOrDefault(R,'P_Shed_NL2',0));
            ylabel(ax, 'Power (kW)');
            xlabel(ax, 'Time step');

            if withLegend
                lgd = legend(ax, {'C_1','N_1','C_2','N_2'});

                applyLegendStyle(lgd);
            end

        case 'DR: AC load shifting'
            % AC non-critical load shifting:
            NL1_orig = getFieldOrDefault(R,'P_NL1',0);
            NL1_adj  = getFieldOrDefault(R,'P_NL1_served', NL1_orig);
            sh1 = NL1_adj - NL1_orig;

            bar(ax, sh1(:));
            hold(ax, 'on');
            plot(ax, NL1_orig(:), 'LineWidth', 1.8);
            plot(ax, NL1_adj(:),  'LineWidth', 1.8);
            hold(ax, 'off');
            xlabel(ax, 'Time interval');
            ylabel(ax, 'Power');
            styleAxes(ax);

            lgd = legend(ax, {'Net shifted (Adj-Orig)','Original NL (AC)','Adjusted NL (AC)'});

            applyLegendStyle(lgd);

        case 'DR: DC load shifting'
            % DC non-critical load shifting:
            NL2_orig = getFieldOrDefault(R,'P_NL2',0);
            NL2_adj  = getFieldOrDefault(R,'P_NL2_served', NL2_orig);
            sh2 = NL2_adj - NL2_orig;

            bar(ax, sh2(:));
            hold(ax, 'on');
            plot(ax, NL2_orig(:), 'LineWidth', 1.8);
            plot(ax, NL2_adj(:),  'LineWidth', 1.8);
            hold(ax, 'off');
            xlabel(ax, 'Time interval');
            ylabel(ax, 'Power');
            styleAxes(ax);

            lgd = legend(ax, {'Net shifted (Adj-Orig)','Original NL (DC)','Adjusted NL (DC)'});

            applyLegendStyle(lgd);

        

        case 'Renewables Curtailment'
            plot(ax, getFieldOrDefault(R,'P_Cur_PV1',0));
            plot(ax, getFieldOrDefault(R,'P_Cur_PV2',0));
            plot(ax, getFieldOrDefault(R,'P_Cur_WT1',0));
            plot(ax, getFieldOrDefault(R,'P_Cur_WT2',0));
            ylabel(ax, 'Power (kW)');
            xlabel(ax, 'Time step');

            if withLegend
                lgd = legend(ax, {'PV_1','PV_2','WT_1','WT_2'});

                applyLegendStyle(lgd);
            end

        
        
        case 'ROB: PV robust (AC/DC)'
            % PV robust view
            pv_unc = getappdata(fig,'pv_unc');
            pv_nom_ac = getFieldOrDefault(R,'P_PV1',0);
            pv_eff_ac = getFieldOrDefault(R,'P_PV1_eff',pv_nom_ac);
            pv_nom_dc = getFieldOrDefault(R,'P_PV2',0);
            pv_eff_dc = getFieldOrDefault(R,'P_PV2_eff',pv_nom_dc);

            pv_rob_ac = pv_nom_ac;
            pv_rob_dc = pv_nom_dc;
            isRobAC = isfield(pv_unc,'AC') && isfield(pv_unc.AC,'mode') && any(strcmpi(string(pv_unc.AC.mode), ["Robust"]));
            isRobDC = isfield(pv_unc,'DC') && isfield(pv_unc.DC,'mode') && any(strcmpi(string(pv_unc.DC.mode), ["Robust"]));
            if isRobAC
                [pv_rob_ac, ~] = budgetRobustProfile(pv_nom_ac, pv_unc.AC, false);
            end
            if isRobDC
                [pv_rob_dc, ~] = budgetRobustProfile(pv_nom_dc, pv_unc.DC, false);
            end

            h = []; lbl = {};
            if any(pv_nom_ac(:)~=0) || any(pv_eff_ac(:)~=0)
                h(end+1) = plot(ax, pv_nom_ac, '-', 'LineWidth', 1); 
                lbl{end+1} = 'PV AC (base)'; 
                if isRobAC
                    h(end+1) = plot(ax, pv_rob_ac, '-', 'LineWidth', 2);
                    lbl{end+1} = 'PV AC (robust)'; 
                else
                    h(end+1) = plot(ax, pv_eff_ac, '-', 'LineWidth', 2); 
                    lbl{end+1} = 'PV AC (used)'; 
                end
            end
            if any(pv_nom_dc(:)~=0) || any(pv_eff_dc(:)~=0)
                h(end+1) = plot(ax, pv_nom_dc, '--', 'LineWidth', 1); 
                lbl{end+1} = 'PV DC (base)'; 
                if isRobDC
                    h(end+1) = plot(ax, pv_rob_dc, '--', 'LineWidth', 2);
                    lbl{end+1} = 'PV DC (robust)'; 
                else
                    h(end+1) = plot(ax, pv_eff_dc, '--', 'LineWidth', 2); 
                    lbl{end+1} = 'PV DC (used)'; 
                end
            end
            xlabel(ax,'Time step'); ylabel(ax,'Power (kW)');
            if withLegend && ~isempty(h)
                lgd = legend(ax, h, lbl, 'Location','best');
                applyLegendStyle(lgd);
            end

        case 'ROB: WT robust (AC/DC)'
            % Wind robust view
            wt_unc = getappdata(fig,'wt_unc');
            wt_nom_ac = getFieldOrDefault(R,'P_WT1',0);
            wt_eff_ac = getFieldOrDefault(R,'P_WT1_eff',wt_nom_ac);
            wt_nom_dc = getFieldOrDefault(R,'P_WT2',0);
            wt_eff_dc = getFieldOrDefault(R,'P_WT2_eff',wt_nom_dc);

            % Recompute robust profiles for plotting
            wt_rob_ac = wt_nom_ac;
            wt_rob_dc = wt_nom_dc;
            isRobAC = isfield(wt_unc,'AC') && isfield(wt_unc.AC,'mode') && any(strcmpi(string(wt_unc.AC.mode), ["Robust"]));
            isRobDC = isfield(wt_unc,'DC') && isfield(wt_unc.DC,'mode') && any(strcmpi(string(wt_unc.DC.mode), ["Robust"]));
            if isRobAC
                [wt_rob_ac, ~] = budgetRobustProfile(wt_nom_ac, wt_unc.AC, false);
            end
            if isRobDC
                [wt_rob_dc, ~] = budgetRobustProfile(wt_nom_dc, wt_unc.DC, false);
            end

            h = []; lbl = {};
            if any(wt_nom_ac(:)~=0) || any(wt_eff_ac(:)~=0)
                h(end+1) = plot(ax, wt_nom_ac, '-', 'LineWidth', 1); 
                lbl{end+1} = 'WT AC (base)'; 
                if isRobAC
                    h(end+1) = plot(ax, wt_rob_ac, '-', 'LineWidth', 2); 
                    lbl{end+1} = 'WT AC (robust)'; 
                else
                    h(end+1) = plot(ax, wt_eff_ac, '-', 'LineWidth', 2); 
                    lbl{end+1} = 'WT AC (used)'; 
                end
            end
            if any(wt_nom_dc(:)~=0) || any(wt_eff_dc(:)~=0)
                h(end+1) = plot(ax, wt_nom_dc, '--', 'LineWidth', 1); 
                lbl{end+1} = 'WT DC (base)'; 
                if isRobDC
                    h(end+1) = plot(ax, wt_rob_dc, '--', 'LineWidth', 2); 
                    lbl{end+1} = 'WT DC (robust)'; 
                else
                    h(end+1) = plot(ax, wt_eff_dc, '--', 'LineWidth', 2); 
                    lbl{end+1} = 'WT DC (used)'; 
                end
            end
            xlabel(ax,'Time step'); ylabel(ax,'Power (kW)');
            if withLegend && ~isempty(h)
                lgd = legend(ax, h, lbl, 'Location','best');
                applyLegendStyle(lgd);
            end

        case 'ROB: Load robust (AC/DC)'
            % Load robust view
            load_unc = getappdata(fig,'load_unc');
            L_nom_ac = getFieldOrDefault(R,'P_CL1',0) + getFieldOrDefault(R,'P_NL1',0);
            L_eff_ac = getFieldOrDefault(R,'P_Load1_eff',L_nom_ac);
            L_nom_dc = getFieldOrDefault(R,'P_CL2',0) + getFieldOrDefault(R,'P_NL2',0);
            L_eff_dc = getFieldOrDefault(R,'P_Load2_eff',L_nom_dc);

            % Recompute robust profiles for plotting
            L_rob_ac = L_nom_ac;
            L_rob_dc = L_nom_dc;
            isRobAC = isfield(load_unc,'AC') && isfield(load_unc.AC,'mode') && any(strcmpi(string(load_unc.AC.mode), ["Robust"]));
            isRobDC = isfield(load_unc,'DC') && isfield(load_unc.DC,'mode') && any(strcmpi(string(load_unc.DC.mode), ["Robust"]));
            if isRobAC
                [L_rob_ac, ~] = budgetRobustProfile(L_nom_ac, load_unc.AC, true);
            end
            if isRobDC
                [L_rob_dc, ~] = budgetRobustProfile(L_nom_dc, load_unc.DC, true);
            end

            h = []; lbl = {};
            if any(L_nom_ac(:)~=0) || any(L_eff_ac(:)~=0)
                h(end+1) = plot(ax, L_nom_ac, '-', 'LineWidth', 1); 
                lbl{end+1} = 'Load AC (base)'; 
                if isRobAC
                    h(end+1) = plot(ax, L_rob_ac, '-', 'LineWidth', 2); 
                    lbl{end+1} = 'Load AC (robust)'; 
                else
                    h(end+1) = plot(ax, L_eff_ac, '-', 'LineWidth', 2); 
                    lbl{end+1} = 'Load AC (used)'; 
                end
            end
            if any(L_nom_dc(:)~=0) || any(L_eff_dc(:)~=0)
                h(end+1) = plot(ax, L_nom_dc, '--', 'LineWidth', 1); 
                lbl{end+1} = 'Load DC (base)'; 
                if isRobDC
                    h(end+1) = plot(ax, L_rob_dc, '--', 'LineWidth', 2); 
                    lbl{end+1} = 'Load DC (robust)'; 
                else
                    h(end+1) = plot(ax, L_eff_dc, '--', 'LineWidth', 2); 
                    lbl{end+1} = 'Load DC (used)'; 
                end
            end
            xlabel(ax,'Time step'); ylabel(ax,'Power (kW)');
            if withLegend && ~isempty(h)
                lgd = legend(ax, h, lbl, 'Location','best');
                applyLegendStyle(lgd);
            end

        case 'UNC: PV scenarios (AC)'
            if isfield(R,'PV1_scen') && ~isempty(R.PV1_scen)
                pvMax = getFieldOrDefaultRaw(R,'PV1_Max',1);
                base  = getFieldOrDefault(R,'P_PV1',0);
                scen  = R.PV1_scen .* pvMax;
                prob  = getFieldOrDefaultRaw(R,'PV1_prob',[]);
                plotScenarioSpaghetti(ax, base, scen, prob, 'PV (AC) scenarios', withLegend);
            else
                showNoScenario(ax, 'PV (AC)');
            end

        case 'UNC: PV scenarios (DC)'
            if isfield(R,'PV2_scen') && ~isempty(R.PV2_scen)
                pvMax = getFieldOrDefaultRaw(R,'PV2_Max',1);
                base  = getFieldOrDefault(R,'P_PV2',0);
                scen  = R.PV2_scen .* pvMax;
                prob  = getFieldOrDefaultRaw(R,'PV2_prob',[]);
                plotScenarioSpaghetti(ax, base, scen, prob, 'PV (DC) scenarios', withLegend);
            else
                showNoScenario(ax, 'PV (DC)');
            end

        case 'UNC: WT scenarios (AC)'
            hasScen = isfield(R,'WT1_scen') && ~isempty(R.WT1_scen);
            if ~hasScen
                try
                    tmp = evalin('base','P_WT1_scen');
                    if ~isempty(tmp)
                        R.WT1_scen = tmp;
                        try; R.WT1_prob = evalin('base','P_WT1_prob'); catch; end
                        hasScen = true;
                    end
                catch
                end
            end
            if hasScen
                wtMax = getFieldOrDefaultRaw(R,'WT1_Max',1);
                base  = getFieldOrDefault(R,'P_WT1',0);
                scen  = R.WT1_scen .* wtMax;
                prob  = getFieldOrDefaultRaw(R,'WT1_prob',[]);
                plotScenarioSpaghetti(ax, base, scen, prob, 'WT (AC) scenarios', withLegend);
            else
                showNoScenario(ax, 'WT (AC)');
            end

        case 'UNC: WT scenarios (DC)'
            hasScen = isfield(R,'WT2_scen') && ~isempty(R.WT2_scen);
            if ~hasScen
                try
                    tmp = evalin('base','P_WT2_scen');
                    if ~isempty(tmp)
                        R.WT2_scen = tmp;
                        try; R.WT2_prob = evalin('base','P_WT2_prob'); catch; end
                        hasScen = true;
                    end
                catch
                end
            end
            if hasScen
                wtMax = getFieldOrDefaultRaw(R,'WT2_Max',1);
                base  = getFieldOrDefault(R,'P_WT2',0);
                scen  = R.WT2_scen .* wtMax;
                prob  = getFieldOrDefaultRaw(R,'WT2_prob',[]);
                plotScenarioSpaghetti(ax, base, scen, prob, 'WT (DC) scenarios', withLegend);
            else
                showNoScenario(ax, 'WT (DC)');
            end

        case 'UNC: Load scenarios (AC)'
            if isfield(R,'Load1_scen') && ~isempty(R.Load1_scen)
                base  = getFieldOrDefault(R,'P_CL1',0) + getFieldOrDefault(R,'P_NL1',0);
                scen  = R.Load1_scen;
                prob  = getFieldOrDefaultRaw(R,'Load1_prob',[]);
                plotScenarioSpaghetti(ax, base, scen, prob, 'Load (AC) scenarios', withLegend);
            else
                showNoScenario(ax, 'Load (AC)');
            end

        case 'UNC: Load scenarios (DC)'
            if isfield(R,'Load2_scen') && ~isempty(R.Load2_scen)
                base  = getFieldOrDefault(R,'P_CL2',0) + getFieldOrDefault(R,'P_NL2',0);
                scen  = R.Load2_scen;
                prob  = getFieldOrDefaultRaw(R,'Load2_prob',[]);
                plotScenarioSpaghetti(ax, base, scen, prob, 'Load (DC) scenarios', withLegend);
            else
                showNoScenario(ax, 'Load (DC)');
            end

        case 'UNC: Scenarios (All AC/DC)'
            % 3x2 grid
            g = uigridlayout(ax.Parent, [3,2]);
            g.RowHeight = {'1x','1x','1x'};
            g.ColumnWidth = {'1x','1x'};
            delete(ax); 

            % PV
            ax1 = uiaxes(g); styleAxes(ax1); ax1.Layout.Row=1; ax1.Layout.Column=1;
            if isfield(R,'PV1_scen') && ~isempty(R.PV1_scen)
                pvMax = getFieldOrDefaultRaw(R,'PV1_Max',1);
                base  = getFieldOrDefault(R,'P_PV1',0);
                scen  = R.PV1_scen .* pvMax;
                prob  = getFieldOrDefaultRaw(R,'PV1_prob',[]);
                plotScenarioSpaghetti(ax1, base, scen, prob, 'PV (AC)', false);
            else
                showNoScenario(ax1,'PV (AC)');
            end
            ax2 = uiaxes(g); styleAxes(ax2); ax2.Layout.Row=1; ax2.Layout.Column=2;
            if isfield(R,'PV2_scen') && ~isempty(R.PV2_scen)
                pvMax = getFieldOrDefaultRaw(R,'PV2_Max',1);
                base  = getFieldOrDefault(R,'P_PV2',0);
                scen  = R.PV2_scen .* pvMax;
                prob  = getFieldOrDefaultRaw(R,'PV2_prob',[]);
                plotScenarioSpaghetti(ax2, base, scen, prob, 'PV (DC)', false);
            else
                showNoScenario(ax2,'PV (DC)');
            end

            % WT
            ax3 = uiaxes(g); styleAxes(ax3); ax3.Layout.Row=2; ax3.Layout.Column=1;
            if ~(isfield(R,'WT1_scen') && ~isempty(R.WT1_scen))
                try
                    tmp = evalin('base','P_WT1_scen');
                    if ~isempty(tmp); R.WT1_scen = tmp; end
                    try; R.WT1_prob = evalin('base','P_WT1_prob'); catch; end
                catch
                end
            end
            if isfield(R,'WT1_scen') && ~isempty(R.WT1_scen)
                wtMax = getFieldOrDefaultRaw(R,'WT1_Max',1);
                base  = getFieldOrDefault(R,'P_WT1',0);
                scen  = R.WT1_scen .* wtMax;
                prob  = getFieldOrDefaultRaw(R,'WT1_prob',[]);
                plotScenarioSpaghetti(ax3, base, scen, prob, 'WT (AC)', false);
            else
                showNoScenario(ax3,'WT (AC)');
            end
            ax4 = uiaxes(g); styleAxes(ax4); ax4.Layout.Row=2; ax4.Layout.Column=2;
            if ~(isfield(R,'WT2_scen') && ~isempty(R.WT2_scen))
                try
                    tmp = evalin('base','P_WT2_scen');
                    if ~isempty(tmp); R.WT2_scen = tmp; end
                    try; R.WT2_prob = evalin('base','P_WT2_prob'); catch; end
                catch
                end
            end
            if isfield(R,'WT2_scen') && ~isempty(R.WT2_scen)
                wtMax = getFieldOrDefaultRaw(R,'WT2_Max',1);
                base  = getFieldOrDefault(R,'P_WT2',0);
                scen  = R.WT2_scen .* wtMax;
                prob  = getFieldOrDefaultRaw(R,'WT2_prob',[]);
                plotScenarioSpaghetti(ax4, base, scen, prob, 'WT (DC)', false);
            else
                showNoScenario(ax4,'WT (DC)');
            end

            % Load
            ax5 = uiaxes(g); styleAxes(ax5); ax5.Layout.Row=3; ax5.Layout.Column=1;
            if isfield(R,'Load1_scen') && ~isempty(R.Load1_scen)
                base  = getFieldOrDefault(R,'P_CL1',0) + getFieldOrDefault(R,'P_NL1',0);
                scen  = R.Load1_scen;
                prob  = getFieldOrDefaultRaw(R,'Load1_prob',[]);
                plotScenarioSpaghetti(ax5, base, scen, prob, 'Load (AC)', false);
            else
                showNoScenario(ax5,'Load (AC)');
            end
            ax6 = uiaxes(g); styleAxes(ax6); ax6.Layout.Row=3; ax6.Layout.Column=2;
            if isfield(R,'Load2_scen') && ~isempty(R.Load2_scen)
                base  = getFieldOrDefault(R,'P_CL2',0) + getFieldOrDefault(R,'P_NL2',0);
                scen  = R.Load2_scen;
                prob  = getFieldOrDefaultRaw(R,'Load2_prob',[]);
                plotScenarioSpaghetti(ax6, base, scen, prob, 'Load (DC)', false);
            else
                showNoScenario(ax6,'Load (DC)');
            end

case 'QSTS: Voltage & Loading'
            if isfield(R,'OpenDSS') && ~isempty(R.OpenDSS) && isfield(R.OpenDSS,'Vmin_pu')
                tIdx = (1:numel(R.OpenDSS.Vmin_pu))';
                yyaxis(ax,'left');
                plot(ax, tIdx, R.OpenDSS.Vmin_pu, '-o', 'MarkerSize', 3);
                plot(ax, tIdx, R.OpenDSS.Vmax_pu, '-o', 'MarkerSize', 3);
                ylabel(ax,'Voltage (pu)');
                try
                    ylim(ax,[0.85 1.15]);
                catch
                end

                yyaxis(ax,'right');
                plot(ax, tIdx, R.OpenDSS.MaxLineLoading_pct, '-');
                plot(ax, tIdx, R.OpenDSS.MaxTrxLoading_pct, '-');
                ylabel(ax,'Loading (%)');
                xlabel(ax,'Time step');

                if withLegend
                    lgd = legend(ax, {'Vmin','Vmax','Max line loading (%)','Max transformer loading'}, 'Location','eastoutside');

                    applyLegendStyle(lgd);
                end
            else
                text(ax,0.1,0.5,'No QSTS results. Enable OpenDSS validation and run optimization.');
                axis(ax,'off');
            end

        case 'QSTS: Voltage min/max'
            if isfield(R,'OpenDSS') && ~isempty(R.OpenDSS) && isfield(R.OpenDSS,'Vmin_pu')
                tIdx = (1:numel(R.OpenDSS.Vmin_pu))';
                plot(ax, tIdx, R.OpenDSS.Vmin_pu, '-o', 'MarkerSize', 3);
                hold(ax,'on');
                plot(ax, tIdx, R.OpenDSS.Vmax_pu, '-o', 'MarkerSize', 3);
                hold(ax,'off');
                ylabel(ax,'Voltage (pu)');
                xlabel(ax,'Time step');
                if withLegend
                    lgd = legend(ax, {'Vmin','Vmax'}, 'Location','eastoutside');

                    applyLegendStyle(lgd);
                end
            else
                text(ax,0.1,0.5,'No QSTS results. Run OpenDSS validation first.');
            end

        case 'QSTS: Losses'
            if isfield(R,'OpenDSS') && ~isempty(R.OpenDSS) && isfield(R.OpenDSS,'Loss_kW')
                tIdx = (1:numel(R.OpenDSS.Loss_kW))';
                plot(ax, tIdx, R.OpenDSS.Loss_kW, '-');
                ylabel(ax,'Losses (kW)');
                xlabel(ax,'Time step');
            else
                text(ax,0.1,0.5,'No QSTS results. Run OpenDSS validation first.');
            end

        case 'QSTS: Line loading'
            if isfield(R,'OpenDSS') && ~isempty(R.OpenDSS) && isfield(R.OpenDSS,'MaxLineLoading_pct')
                tIdx = (1:numel(R.OpenDSS.MaxLineLoading_pct))';
                plot(ax, tIdx, R.OpenDSS.MaxLineLoading_pct, '-');
                ylabel(ax,'Max line loading (%)');
                xlabel(ax,'Time step');
            else
                text(ax,0.1,0.5,'No QSTS results. Run OpenDSS validation first.');
            end

        case 'QSTS: Transformer loading'
            if isfield(R,'OpenDSS') && ~isempty(R.OpenDSS) && isfield(R.OpenDSS,'MaxTrxLoading_pct')
                tIdx = (1:numel(R.OpenDSS.MaxTrxLoading_pct))';
                plot(ax, tIdx, R.OpenDSS.MaxTrxLoading_pct, '-');
                ylabel(ax,'Max transformer loading (%)');
                xlabel(ax,'Time step');
            else
                text(ax,0.1,0.5,'No QSTS results. Run OpenDSS validation first.');
            end

        case 'QSTS: Bus voltages (t)'
            if isfield(R,'OpenDSS') && ~isempty(R.OpenDSS) && isfield(R.OpenDSS,'BusVpu')
                tShow = 1;
                try
                    tShow = max(1, min(size(R.OpenDSS.BusVpu,2), round(dssTimeField.Value)));
                catch
                end
                v = R.OpenDSS.BusVpu(:,tShow);
                plot(ax, v, '-');
                ylabel(ax,'Voltage (pu)');
                xlabel(ax,'Bus index');
            else
                text(ax,0.1,0.5,'No QSTS results. Run QSTS first.');
            end

        case 'QSTS: Node voltages (t)'
            if isfield(R,'OpenDSS') && ~isempty(R.OpenDSS) && isfield(R.OpenDSS,'NodeVpu')
                tShow = 1;
                try
                    tShow = max(1, min(size(R.OpenDSS.NodeVpu,2), round(dssTimeField.Value)));
                catch
                end
                v = R.OpenDSS.NodeVpu(:,tShow);
                plot(ax, v, '-');
                ylabel(ax,'Voltage (pu)');
                xlabel(ax,'Node index');
            else
                text(ax,0.1,0.5,'No QSTS results. Run QSTS first.');
            end

        case 'Electricity prices'
            % Plot buying and selling electricity prices (one-day horizon: 96 intervals)
            nT = 96;
            t = (1:nT)';

            buy  = getFieldOrDefaultRaw(R,'Elec_Price',[]);
            sell = getFieldOrDefaultRaw(R,'Elec_SellPrice',[]);

            if isempty(buy)
                try buy = evalin('base','Elec_Price'); catch, buy = []; end
            end
            if isempty(sell)
                try sell = evalin('base','Elec_SellPrice'); catch, sell = []; end
            end

            buy  = localEnsureColT(buy, nT);
            sell = localEnsureColT(sell, nT);

            plot(ax, t, buy, '-');
            plot(ax, t, sell, '--');
            xlabel(ax,'Interval (15 min)'); ylabel(ax,'Price');
            title(ax,'Electricity Prices (Buy vs Sell)');
            if withLegend
                legend(ax, {'Buy price','Sell price'}, 'Location','best');
            end

        otherwise
    end
end

function pos = getPlotLabelPos(figHandle, plotPosN)
    dd = getPlotSelectorPos(figHandle, plotPosN);
    labelW = 90;
    gap = 8;
    pos = [max(10, dd(1)-gap-labelW), dd(2)+3, labelW, dd(4)-6];
end

function pos = getPlotSelectorPos(figHandle, plotPosN)
    figW = figHandle.Position(3);
    figH = figHandle.Position(4);
    x = plotPosN(1)*figW + plotPosN(3)*figW - 260;
    y = plotPosN(2)*figH + plotPosN(4)*figH + 8;  
    pos = [max(10, x), max(10, y), 250, 26];
end

ax1.ActivePositionProperty = 'position';
ax2.ActivePositionProperty = 'position';
ax3.ActivePositionProperty = 'position';
ax4.ActivePositionProperty = 'position';

    
    function openGridDialog()
        d = buildDialog('Grid Settings', 3);
        g = getappdata(d,'app_grid');

        [~, fGrid] = addNumericRow(g, 1, 'P_{grid,max} (kW):', PGridMaxField.Value);

        load_unc = getappdata(fig,'load_unc');
        if isempty(load_unc)
            load_unc = struct();
            load_unc.AC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6,'crit_pct',30);
            load_unc.DC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6,'crit_pct',30);
            setappdata(fig,'load_unc', load_unc);
        end
        uiwait(d);
        if isvalid(d) && getappdata(d,'app_save')
            PGridMaxField.Value = fGrid.Value;
        end
        if isvalid(d); delete(d); end
    end

    function openLoadDialog(side, statusLbl)
        if nargin < 2; statusLbl = []; end
        load_unc = getappdata(fig,'load_unc');
        if isempty(load_unc)
            load_unc = struct();
            load_unc.AC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6,'crit_pct',30);
            load_unc.DC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6,'crit_pct',30);
        end

        if strcmpi(side,'AC')
            cur = load_unc.AC;
            titleStr = 'AC Load Settings';
        else
            cur = load_unc.DC;
            titleStr = 'DC Load Settings';
        end

        d = buildDialog(titleStr, 7);
        g = getappdata(d,'app_grid');

        % Mode dropdown
        lbl = uilabel(g,'Text','Uncertainty mode:','FontSize',12);
        lbl.Layout.Row = 1; lbl.Layout.Column = 1;
        ddMode = uidropdown(g,'Items',{'Deterministic','Stochastic','Robust'},'Value',char(cur.mode));
        ddMode.Layout.Row = 1; ddMode.Layout.Column = 2;

        [~, fLvl]  = addNumericRow(g, 2, 'Level (0–1):', cur.level);
        [~, fNum]  = addNumericRow(g, 3, '# Scenarios:', cur.num_scen);
        [~, fSeed] = addNumericRow(g, 4, 'Seed:', cur.seed);
        [~, fRho]  = addNumericRow(g, 5, 'Correlation rho (0–0.99):', cur.rho);
        [~, fGam]  = addNumericRow(g, 6, 'Robust Gamma (time-steps):', cur.gamma);
        [~, fPct]  = addNumericRow(g, 7, 'Critical load (% of total):', cur.crit_pct);
        try; fPct.Limits = [0 100]; catch; end

        uiwait(d);
        if isvalid(d) && getappdata(d,'app_save')
            cur.mode = ddMode.Value;
            cur.level = max(0, min(1, fLvl.Value));
            cur.num_scen = max(1, round(fNum.Value));
            cur.seed = round(fSeed.Value);
            cur.rho = max(0, min(0.99, fRho.Value));
            cur.gamma = max(0, round(fGam.Value));
            cur.crit_pct = max(0, min(100, fPct.Value));

            if strcmpi(side,'AC')
                load_unc.AC = cur;
            else
                load_unc.DC = cur;
            end
            setappdata(fig,'load_unc', load_unc);

            try
                statusLbl.Text = sprintf('%s Load: critical %.0f%%, mode=%s', upper(side), cur.crit_pct, char(cur.mode));
            catch
            end
        end
        if isvalid(d); delete(d); end
    end

    function openDRDialog(side)
        % DR settings are configured via this popup 
        if strcmpi(side,'AC')
            d = buildDialog('DR (AC) Settings', 4);
            g = getappdata(d,'app_grid');
            [~, fPct]  = addNumericRow(g, 1, 'Shiftable non-critical load (%) :', getUIValue(drACPctField,0));
            [~, fFlex] = addNumericRow(g, 2, 'Flexibility DR\_flex (0-2):', getUIValue(drACFlexField, 1));
            [~, fLam]  = addNumericRow(g, 3, 'Deviation penalty \lambda\_{DR} (₩/kW):', drACLambdaField.Value);
            [~, fRamp] = addNumericRow(g, 4, 'Ramp fraction (0-1):', drACRampFracField.Value);
            try; fPct.Limits  = [0 100]; catch; end
            try; fFlex.Limits = [0 2];   catch; end
            try; fLam.Limits  = [0 inf]; catch; end
            try; fRamp.Limits = [0 1];   catch; end
            uiwait(d);
            if isvalid(d) && getappdata(d,'app_save')
                drACPctField.Value = max(0, min(100, fPct.Value));
                drACFlexField.Value = max(0, min(2,   fFlex.Value));
                drACLambdaField.Value   = max(0,          fLam.Value);
                drACRampFracField.Value = max(0, min(1,   fRamp.Value));
            drACPctDispLbl.Text = sprintf('%.0f%%', max(0,min(100,getUIValue(drACPctField,0))));
            end
            if isvalid(d); delete(d); end
        else
            d = buildDialog('DR (DC) Settings', 4);
            g = getappdata(d,'app_grid');
            [~, fPct]  = addNumericRow(g, 1, 'Shiftable non-critical load (%) :', getUIValue(drDCPctField,0));
            [~, fFlex] = addNumericRow(g, 2, 'Flexibility DR\_flex (0-2):', getUIValue(drDCFlexField, 1));
            [~, fLam]  = addNumericRow(g, 3, 'Deviation penalty \lambda\_{DR} (₩/kW):', drDCLambdaField.Value);
            [~, fRamp] = addNumericRow(g, 4, 'Ramp fraction (0-1):', drDCRampFracField.Value);
            try; fPct.Limits  = [0 100]; catch; end
            try; fFlex.Limits = [0 2];   catch; end
            try; fLam.Limits  = [0 inf]; catch; end
            try; fRamp.Limits = [0 1];   catch; end
            uiwait(d);
            if isvalid(d) && getappdata(d,'app_save')
                drDCPctField.Value = max(0, min(100, fPct.Value));
                drDCFlexField.Value = max(0, min(2,   fFlex.Value));
                drDCLambdaField.Value   = max(0,          fLam.Value);
                drDCRampFracField.Value = max(0, min(1,   fRamp.Value));
            drDCPctDispLbl.Text = sprintf('%.0f%%', max(0,min(100,getUIValue(drDCPctField,0))));
            end
            if isvalid(d); delete(d); end
        end
        refreshDRControls();
    end

function openPVDialog(side)
        % PV Configure… dialog with uncertainty options (PV only).
        pv_unc = getappdata(fig,'pv_unc');
        if isempty(pv_unc)
            pv_unc = struct();
            pv_unc.AC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6);
            pv_unc.DC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6);
        end

        if strcmpi(side,'AC')
            cur = pv_unc.AC;
            d = buildDialog('PV (AC) Settings', 7);
            g = getappdata(d,'app_grid');

            [~, fPmax]   = addNumericRow(g, 1, 'Rated Power (kW):', PV1maxField.Value);

            % Uncertainty mode
            lbl = uilabel(g, 'Text', 'Uncertainty mode:', 'FontSize', 12);
            lbl.Layout.Row = 2; lbl.Layout.Column = 1;
            if isfield(cur,'mode') && (strcmpi(string(cur.mode),'Scenario') || strcmpi(string(cur.mode),'Stocastic'))
    cur.mode = 'Stochastic';
end
ddMode = uidropdown(g, 'Items', {'Deterministic','Stochastic','Robust'}, 'Value', string(cur.mode));
            ddMode.Layout.Row = 2; ddMode.Layout.Column = 2;

            [~, fLevel]  = addNumericRow(g, 3, 'Uncertainty level (0–1):', cur.level);
            [~, fScen]   = addNumericRow(g, 4, '# scenarios (Scenario):', cur.num_scen);
            [~, fSeed]   = addNumericRow(g, 5, 'Seed (Scenario):', cur.seed);
            [~, fRho]    = addNumericRow(g, 6, 'rho (0–0.99, Scenario):', cur.rho);
            [~, fGamma]  = addNumericRow(g, 7, 'Gamma (Robust):', cur.gamma);

            uiwait(d);
            if isvalid(d) && getappdata(d,'app_save')
                PV1maxField.Value = fPmax.Value;

                cur.mode     = ddMode.Value;
                cur.level    = max(0, min(1, fLevel.Value));
                cur.num_scen = max(1, round(fScen.Value));
                cur.seed     = max(0, round(fSeed.Value));
                cur.rho      = max(0, min(0.99, fRho.Value));
                cur.gamma    = max(0, round(fGamma.Value));

                pv_unc.AC = cur;
                setappdata(fig,'pv_unc', pv_unc);
            end
            if isvalid(d); delete(d); end

        else
            cur = pv_unc.DC;
            d = buildDialog('PV (DC) Settings', 7);
            g = getappdata(d,'app_grid');

            [~, fPmax]   = addNumericRow(g, 1, 'Rated Power (kW):', PV2maxField.Value);

            lbl = uilabel(g, 'Text', 'Uncertainty mode:', 'FontSize', 12);
            lbl.Layout.Row = 2; lbl.Layout.Column = 1;
            if isfield(cur,'mode') && (strcmpi(string(cur.mode),'Scenario') || strcmpi(string(cur.mode),'Stocastic'))
    cur.mode = 'Stochastic';
end
ddMode = uidropdown(g, 'Items', {'Deterministic','Stochastic','Robust'}, 'Value', string(cur.mode));
            ddMode.Layout.Row = 2; ddMode.Layout.Column = 2;

            [~, fLevel]  = addNumericRow(g, 3, 'Uncertainty level (0–1):', cur.level);
            [~, fScen]   = addNumericRow(g, 4, '# scenarios (Scenario):', cur.num_scen);
            [~, fSeed]   = addNumericRow(g, 5, 'Seed (Scenario):', cur.seed);
            [~, fRho]    = addNumericRow(g, 6, 'rho (0–0.99, Scenario):', cur.rho);
            [~, fGamma]  = addNumericRow(g, 7, 'Gamma (Robust):', cur.gamma);

            uiwait(d);
            if isvalid(d) && getappdata(d,'app_save')
                PV2maxField.Value = fPmax.Value;

                cur.mode     = ddMode.Value;
                cur.level    = max(0, min(1, fLevel.Value));
                cur.num_scen = max(1, round(fScen.Value));
                cur.seed     = max(0, round(fSeed.Value));
                cur.rho      = max(0, min(0.99, fRho.Value));
                cur.gamma    = max(0, round(fGamma.Value));

                pv_unc.DC = cur;
                setappdata(fig,'pv_unc', pv_unc);
            end
            if isvalid(d); delete(d); end
        end
    end

    function openWTDialog(side)
        wt_unc = getappdata(fig,'wt_unc');
        if isempty(wt_unc)
            wt_unc = struct();
            wt_unc.AC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6);
            wt_unc.DC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6);
        end

        if strcmpi(side,'AC')
            unc = wt_unc.AC;
            d = buildDialog('WT (AC) Settings', 8);
            g = getappdata(d,'app_grid');
            [~, fP] = addNumericRow(g, 1, 'Rated Power (kW):', Wind1maxField.Value);

            lblM = uilabel(g,'Text','Uncertainty mode:','FontSize',12);
            lblM.Layout.Row = 2; lblM.Layout.Column = 1;
            ddMode = uidropdown(g,'Items',{'Deterministic','Stochastic','Robust'},'Value',char(unc.mode));
            ddMode.Layout.Row = 2; ddMode.Layout.Column = 2;

            [~, fLvl]  = addNumericRow(g, 3, 'Level (0–1):', unc.level);
            [~, fNum]  = addNumericRow(g, 4, '# Scenarios:', unc.num_scen);
            [~, fSeed] = addNumericRow(g, 5, 'Seed:', unc.seed);
            [~, fRho]  = addNumericRow(g, 6, 'Correlation rho (0–0.99):', unc.rho);
            [~, fGam]  = addNumericRow(g, 7, 'Robust Gamma (time-steps):', unc.gamma);

            note = uilabel(g,'Text','Scenario uses expected WT; Robust reduces top-Gamma WT','FontSize',13,'FontColor',[0.3 0.3 0.3]);
            note.Layout.Row = 8; note.Layout.Column = 1;
            spacer = uilabel(g,'Text',''); spacer.Layout.Row = 8; spacer.Layout.Column = 2;

            uiwait(d);
            if isvalid(d) && getappdata(d,'app_save')
                Wind1maxField.Value = fP.Value;
                wt_unc.AC.mode = ddMode.Value;
                wt_unc.AC.level = fLvl.Value;
                wt_unc.AC.num_scen = fNum.Value;
                wt_unc.AC.seed = fSeed.Value;
                wt_unc.AC.rho = fRho.Value;
                wt_unc.AC.gamma = fGam.Value;
                setappdata(fig,'wt_unc', wt_unc);
            end
            if isvalid(d); delete(d); end
        else
            unc = wt_unc.DC;
            d = buildDialog('WT (DC) Settings', 8);
            g = getappdata(d,'app_grid');
            [~, fP] = addNumericRow(g, 1, 'Rated Power (kW):', Wind2maxField.Value);

            lblM = uilabel(g,'Text','Uncertainty mode:','FontSize',12);
            lblM.Layout.Row = 2; lblM.Layout.Column = 1;
            ddMode = uidropdown(g,'Items',{'Deterministic','Stochastic','Robust'},'Value',char(unc.mode));
            ddMode.Layout.Row = 2; ddMode.Layout.Column = 2;

            [~, fLvl]  = addNumericRow(g, 3, 'Level (0–1):', unc.level);
            [~, fNum]  = addNumericRow(g, 4, '# Scenarios:', unc.num_scen);
            [~, fSeed] = addNumericRow(g, 5, 'Seed:', unc.seed);
            [~, fRho]  = addNumericRow(g, 6, 'Correlation rho (0–0.99):', unc.rho);
            [~, fGam]  = addNumericRow(g, 7, 'Robust Gamma (time-steps):', unc.gamma);

            note = uilabel(g,'Text','Scenario uses expected WT; Robust reduces top-Gamma WT','FontSize',13,'FontColor',[0.3 0.3 0.3]);
            note.Layout.Row = 8; note.Layout.Column = 1;
            spacer = uilabel(g,'Text',''); spacer.Layout.Row = 8; spacer.Layout.Column = 2;

            uiwait(d);
            if isvalid(d) && getappdata(d,'app_save')
                Wind2maxField.Value = fP.Value;
                wt_unc.DC.mode = ddMode.Value;
                wt_unc.DC.level = fLvl.Value;
                wt_unc.DC.num_scen = fNum.Value;
                wt_unc.DC.seed = fSeed.Value;
                wt_unc.DC.rho = fRho.Value;
                wt_unc.DC.gamma = fGam.Value;
                setappdata(fig,'wt_unc', wt_unc);
            end
            if isvalid(d); delete(d); end
        end
    end

function openCDGDialog()
        % MT (AC) settings: single AC-side MT (fuel type selectable).
        d = buildDialog('MT AC Settings', 6);
        g = getappdata(d,'app_grid');

        g.RowHeight = {'fit','fit','fit','fit','fit','fit'};
        g.ColumnWidth = {'1x','1x'};

        % Header
        lblP = uilabel(g,'Text','Parameter','FontSize',12,'FontWeight','bold','HorizontalAlignment','left');
        lblP.Layout.Row = 1; lblP.Layout.Column = 1;
        lblV = uilabel(g,'Text','Value','FontSize',12,'FontWeight','bold','HorizontalAlignment','left');
        lblV.Layout.Row = 1; lblV.Layout.Column = 2;

        % Fuel type
        u1 = uilabel(g,'Text','Fuel type','HorizontalAlignment','left');
        u1.Layout.Row = 2; u1.Layout.Column = 1;
        ddFuel = uidropdown(g,'Items',{'Gas','Diesel','Hydrogen'},'Value',MT_AC_fuel{1});
        ddFuel.Layout.Row = 2; ddFuel.Layout.Column = 2;

        % alpha
        u2 = uilabel(g,'Text','alpha','HorizontalAlignment','left');
        u2.Layout.Row = 3; u2.Layout.Column = 1;
        fA = uieditfield(g,'numeric','Value',MT_AC_alpha(1));
        fA.Layout.Row = 3; fA.Layout.Column = 2;

        % beta
        u3 = uilabel(g,'Text','beta','HorizontalAlignment','left');
        u3.Layout.Row = 4; u3.Layout.Column = 1;
        fB = uieditfield(g,'numeric','Value',MT_AC_beta(1));
        fB.Layout.Row = 4; fB.Layout.Column = 2;

        % gamma
        u4 = uilabel(g,'Text','gamma','HorizontalAlignment','left');
        u4.Layout.Row = 5; u4.Layout.Column = 1;
        fG = uieditfield(g,'numeric','Value',MT_AC_gamma(1));
        fG.Layout.Row = 5; fG.Layout.Column = 2;

        % Rated Power
        u5 = uilabel(g,'Text','Rated Power','HorizontalAlignment','left');
        u5.Layout.Row = 6; u5.Layout.Column = 1;
        fP = uieditfield(g,'numeric','Value',MT_AC_Pmax(1));
        fP.Layout.Row = 6; fP.Layout.Column = 2;

        uiwait(d);
        if isvalid(d) && getappdata(d,'app_save')
            MT_AC_fuel{1}  = ddFuel.Value;
            MT_AC_alpha(1) = fA.Value;
            MT_AC_beta(1)  = fB.Value;
            MT_AC_gamma(1) = fG.Value;
            MT_AC_Pmax(1)  = fP.Value;
        end
        if isvalid(d); delete(d); end
end
function openMT2Dialog()
        % MT (DC) settings: single DC-side MT (fuel type selectable).
        d = buildDialog('MT DC Settings', 6);
        g = getappdata(d,'app_grid');

        g.RowHeight = {'fit','fit','fit','fit','fit','fit'};
        g.ColumnWidth = {'1x','1x'};

        % Header
        lblP = uilabel(g,'Text','Parameter','FontSize',12,'FontWeight','bold','HorizontalAlignment','left');
        lblP.Layout.Row = 1; lblP.Layout.Column = 1;
        lblV = uilabel(g,'Text','Value','FontSize',12,'FontWeight','bold','HorizontalAlignment','left');
        lblV.Layout.Row = 1; lblV.Layout.Column = 2;

        % Fuel type
        u1 = uilabel(g,'Text','Fuel type','HorizontalAlignment','left');
        u1.Layout.Row = 2; u1.Layout.Column = 1;
        ddFuel = uidropdown(g,'Items',{'Gas','Diesel','Hydrogen'},'Value',MT_DC_fuel{1});
        ddFuel.Layout.Row = 2; ddFuel.Layout.Column = 2;

        % alpha
        u2 = uilabel(g,'Text','alpha','HorizontalAlignment','left');
        u2.Layout.Row = 3; u2.Layout.Column = 1;
        fA = uieditfield(g,'numeric','Value',MT_DC_alpha(1));
        fA.Layout.Row = 3; fA.Layout.Column = 2;

        % beta
        u3 = uilabel(g,'Text','beta','HorizontalAlignment','left');
        u3.Layout.Row = 4; u3.Layout.Column = 1;
        fB = uieditfield(g,'numeric','Value',MT_DC_beta(1));
        fB.Layout.Row = 4; fB.Layout.Column = 2;

        % gamma
        u4 = uilabel(g,'Text','gamma','HorizontalAlignment','left');
        u4.Layout.Row = 5; u4.Layout.Column = 1;
        fG = uieditfield(g,'numeric','Value',MT_DC_gamma(1));
        fG.Layout.Row = 5; fG.Layout.Column = 2;

        % Rated Power
        u5 = uilabel(g,'Text','Rated Power','HorizontalAlignment','left');
        u5.Layout.Row = 6; u5.Layout.Column = 1;
        fP = uieditfield(g,'numeric','Value',MT_DC_Pmax(1));
        fP.Layout.Row = 6; fP.Layout.Column = 2;

        uiwait(d);
        if isvalid(d) && getappdata(d,'app_save')
            MT_DC_fuel{1}  = ddFuel.Value;
            MT_DC_alpha(1) = fA.Value;
            MT_DC_beta(1)  = fB.Value;
            MT_DC_gamma(1) = fG.Value;
            MT_DC_Pmax(1)  = fP.Value;
        end
        if isvalid(d); delete(d); end
end
    function openBESSDialog(side)
        if strcmpi(side,'AC')
            d = buildDialog('BESS (AC) Settings', 6);
            g = getappdata(d,'app_grid');
            [~, fMin] = addNumericRow(g, 1, 'SoC Low (%):', SOC1MinField.Value);
            [~, fMax] = addNumericRow(g, 2, 'SoC High (%):', SOC1MaxField.Value);
            [~, fIni] = addNumericRow(g, 3, 'SoC Init (%):', SOC1InitField.Value);
            [~, fCap] = addNumericRow(g, 4, 'Capacity (kWh):', CAP1Field.Value);
            [~, fPow] = addNumericRow(g, 5, 'Power (kW):', PBESS1MaxField.Value);
            [~, fEff] = addNumericRow(g, 6, 'Efficiency (%):', EffBESS1Field.Value);
            uiwait(d);
            if isvalid(d) && getappdata(d,'app_save')
                SOC1MinField.Value = fMin.Value;
                SOC1MaxField.Value = fMax.Value;
                SOC1InitField.Value = fIni.Value;
                CAP1Field.Value = fCap.Value;
                PBESS1MaxField.Value = fPow.Value;
                EffBESS1Field.Value = fEff.Value;
            end
            if isvalid(d); delete(d); end
        else
            d = buildDialog('BESS (DC) Settings', 6);
            g = getappdata(d,'app_grid');
            [~, fMin] = addNumericRow(g, 1, 'SoC Low (%):', SOC2MinField.Value);
            [~, fMax] = addNumericRow(g, 2, 'SoC High (%):', SOC2MaxField.Value);
            [~, fIni] = addNumericRow(g, 3, 'SoC Init (%):', SOC2InitField.Value);
            [~, fCap] = addNumericRow(g, 4, 'Capacity (kWh):', CAP2Field.Value);
            [~, fPow] = addNumericRow(g, 5, 'Power (kW):', PBESS2MaxField.Value);
            [~, fEff] = addNumericRow(g, 6, 'Efficiency (%):', EffBESS2Field.Value);
            uiwait(d);
            if isvalid(d) && getappdata(d,'app_save')
                SOC2MinField.Value = fMin.Value;
                SOC2MaxField.Value = fMax.Value;
                SOC2InitField.Value = fIni.Value;
                CAP2Field.Value = fCap.Value;
                PBESS2MaxField.Value = fPow.Value;
                EffBESS2Field.Value = fEff.Value;
            end
            if isvalid(d); delete(d); end
        end
    end

    function openEVDialog(side)
        if strcmpi(side,'AC')
            % ===== AC EV Fleet configuration (N + per-EV parameter table) =====
            d = uifigure('Name','EV (AC) Fleet Settings','Position',[200 150 760 420], ...
                        'Resize','off','WindowStyle','modal');

            curN = max(1, round(getUIValue(NEV_ACField, 1)));
            if exist('EVACTable','var') && ~isempty(EVACTable) && isgraphics(EVACTable) && ~isempty(EVACTable.Data)
                curD = EVACTable.Data;
            else
                curD = defaultEVACData(curN);
            end

            % Top row: N selector
            uilabel(d,'Position',[20 380 200 22],'Text','Number of AC-side EVs (N):','FontSize',13);
            spN = uispinner(d,'Limits',[1 50],'Step',1,'Value',curN,'Position',[230 380 80 24],'FontSize',13);

            % Table (rows=EVs, cols=params)
            evColNames = {'Pmax_kW','Eff','Cap_kWh','SOC_init','SOC_min','SOC_max','SOC_target','Arr_h','Dep_h'};
            tbl = uitable(d, 'Data', curD, 'ColumnName', evColNames, ...
                          'ColumnEditable', true(1,numel(evColNames)), ...
                          'Position', [20 70 720 295], 'FontSize', 12);

            localEVSyncRows(spN, tbl, @defaultEVACData);

            spN.ValueChangedFcn = @(~,~) localEVSyncRows(spN, tbl, @defaultEVACData);
            btnSave = uibutton(d,'Text','Save','Position',[560 20 80 30],'FontSize',13, ...
                               'ButtonPushedFcn', @(~,~) localEVSave(spN, tbl, d, NEV_ACField, EVACTable, ...
                               EV1MaxField, EffEV1Field, EV1CapField, EV1SOCInitField, EV1SOCMinField, EV1SOCMaxField, ...
                               EV1SOCTarField, EV1ARRField, EV1DEPField, @defaultEVACData));
            btnCancel = uibutton(d,'Text','Cancel','Position',[650 20 90 30],'FontSize',13, ...
                                 'ButtonPushedFcn', @(~,~) localCloseDialog(d));

            uiwait(d);
            if isvalid(d); delete(d); end

        else
            % ===== DC EV Fleet configuration (N + per-EV parameter table) =====
            d = uifigure('Name','EV (DC) Fleet Settings','Position',[220 170 760 420], ...
                        'Resize','off','WindowStyle','modal');

            curN = max(1, round(getUIValue(NEV_DCField, 1)));
            if exist('EVDCTable','var') && ~isempty(EVDCTable) && isgraphics(EVDCTable) && ~isempty(EVDCTable.Data)
                curD = EVDCTable.Data;
            else
                curD = defaultEVDCData(curN);
            end

            uilabel(d,'Position',[20 380 220 22],'Text','Number of DC-side EVs (N):','FontSize',13);
            spN = uispinner(d,'Limits',[1 50],'Step',1,'Value',curN,'Position',[250 380 80 24],'FontSize',13);

            evColNames = {'Pmax_kW','Eff','Cap_kWh','SOC_init','SOC_min','SOC_max','SOC_target','Arr_h','Dep_h'};
            tbl = uitable(d, 'Data', curD, 'ColumnName', evColNames, ...
                          'ColumnEditable', true(1,numel(evColNames)), ...
                          'Position', [20 70 720 295], 'FontSize', 12);

            localEVSyncRows(spN, tbl, @defaultEVDCData);
            spN.ValueChangedFcn = @(~,~) localEVSyncRows(spN, tbl, @defaultEVDCData);

            btnSave = uibutton(d,'Text','Save','Position',[560 20 80 30],'FontSize',13, ...
                               'ButtonPushedFcn', @(~,~) localEVSave(spN, tbl, d, NEV_DCField, EVDCTable, ...
                               EV2MaxField, EffEV2Field, [], EV2SOCInitField, EV2SOCMinField, EV2SOCMaxField, ...
                               EV2SOCTarField, EV2ARRField, EV2DEPField, @defaultEVDCData));
            btnCancel = uibutton(d,'Text','Cancel','Position',[650 20 90 30],'FontSize',13, ...
                                 'ButtonPushedFcn', @(~,~) localCloseDialog(d));

            uiwait(d);
            if isvalid(d); delete(d); end

        end
    end

    function openILCDialog()
        d = buildDialog('ILC (AC↔DC) Settings', 2);
        g = getappdata(d,'app_grid');
        [~, fP] = addNumericRow(g, 1, 'Rated Power (kW):', PConvMaxField.Value);
        [~, fE] = addNumericRow(g, 2, 'Efficiency (%):', EffConvField.Value);
        uiwait(d);
        if isvalid(d) && getappdata(d,'app_save')
            PConvMaxField.Value = fP.Value;
            EffConvField.Value  = fE.Value;
        end
        if isvalid(d); delete(d); end
    end

    % % Utility (GUI helpers)
    function pos = centerPos(parentFig, w, h)
        try
            pf = parentFig.Position;
            x = pf(1) + (pf(3) - w)/2;
            y = pf(2) + (pf(4) - h)/2;
        catch
            x = 100; y = 100;
        end
        try
            scr = get(groot,'ScreenSize'); 
            x = max(scr(1)+20, min(x, scr(3)-w-20));
            y = max(scr(2)+40, min(y, scr(4)-h-60));
        catch
        end
        pos = [x y w h];
    end

    

    % ===== PV Uncertainty helpers (PV only) =====
    function [pv_eff, pv_scen, scenProb] = applyPVUncertainty(pv_nom, unc)
        pv_nom = pv_nom(:);
        pv_eff = pv_nom;
        pv_scen = [];
        scenProb = [];

        if isempty(unc) || ~isfield(unc,'mode'); return; end
        modeStr = lower(strtrim(string(unc.mode)));

        if ismember(modeStr, ["scenario","stochastic","stocastic"])
            S = max(1, round(getNumericScalar(getFieldOrDefaultRaw(unc,'num_scen',10),10)));
            level = max(0, min(1, getNumericScalar(getFieldOrDefaultRaw(unc,'level',0.10),0.10)));
            seed = max(0, round(getNumericScalar(getFieldOrDefaultRaw(unc,'seed',1),1)));
            rho = max(0, min(0.99, getNumericScalar(getFieldOrDefaultRaw(unc,'rho',0.70),0.70)));

            [pv_scen, scenProb] = makePVScenarios(pv_nom, level, S, seed, rho);
            pv_eff = pv_scen * scenProb(:);

        elseif modeStr == "robust"
            level = max(0, min(1, getNumericScalar(getFieldOrDefaultRaw(unc,'level',0.10),0.10)));
            gamma = max(0, round(getNumericScalar(getFieldOrDefaultRaw(unc,'gamma',6),6)));
            pv_eff = robustPVProfile(pv_nom, level, gamma); 
        end
        pv_eff = max(0, min(1, pv_eff));
    end

    function [pv_scen, scenProb] = makePVScenarios(pv_nom, level, S, seed, rho)
        pv_nom = pv_nom(:);
        N = numel(pv_nom);
        rng(seed);

        pv_scen = zeros(N, S);
        scenProb = (1/S) * ones(1, S);

        sig = level;  
        for s = 1:S
            e = zeros(N,1);
            for k = 2:N
                e(k) = rho*e(k-1) + sqrt(max(0,1-rho^2))*sig*randn();
            end
            e = max(-3*sig, min(3*sig, e));
            pv_s = pv_nom .* (1 + e);
            pv_scen(:,s) = max(0, min(1, pv_s));
        end
    end

    
    function [rob, ok] = budgetRobustProfile(baseProf, sideUnc, isLoad)
        ok = false;
        rob = baseProf(:);
        if isempty(sideUnc) || ~isstruct(sideUnc) || ~isfield(sideUnc,'mode')
            return;
        end
        modeStr = lower(strtrim(string(sideUnc.mode)));
        if modeStr ~= "robust"
            return;
        end
        level = max(0, min(1, getNumericScalar(getFieldOrDefaultRaw(sideUnc,'level',0.10),0.10)));
        gamma = max(0, round(getNumericScalar(getFieldOrDefaultRaw(sideUnc,'gamma',0),0)));
        N = numel(rob);
        gamma = min(gamma, N);
        if gamma <= 0 || level <= 0
            ok = true;
            return;
        end
        [~, idx] = sort(rob, 'descend');
        sel = idx(1:gamma);
        if isLoad
            rob(sel) = rob(sel) * (1 + level);
        else
            rob(sel) = rob(sel) * (1 - level);
        end
        ok = true;
    end

function pv_rob = robustPVProfile(pv_nom, level, gamma)
        % Budgeted worst-case: reduce PV by 'level' on the top 'gamma' PV periods.
        pv_nom = pv_nom(:);
        N = numel(pv_nom);
        pv_rob = pv_nom;
        gamma = min(max(0, gamma), N);
        if gamma == 0 || level <= 0
            return;
        end
        [~, idx] = sort(pv_nom, 'descend');
        sel = idx(1:gamma);
        pv_rob(sel) = pv_nom(sel) * (1 - level);
        pv_rob = max(0, min(1, pv_rob));
    end

    % ===== WT Uncertainty helpers (WT only) =====
    function [wt_eff, wt_scen, scenProb] = applyWTUncertainty(wt_nom, unc)
        wt_nom = wt_nom(:);
        wt_eff = wt_nom;
        wt_scen = [];
        scenProb = [];

        if isempty(unc) || ~isfield(unc,'mode')
            return;
        end

        modeStr = lower(strtrim(string(unc.mode)));

        level = max(0, min(1, getNumericScalar(getFieldOrDefaultRaw(unc,'level',0.10), 0.10)));
        S     = max(1, round(getNumericScalar(getFieldOrDefaultRaw(unc,'num_scen',10), 10)));
        seed  = round(getNumericScalar(getFieldOrDefaultRaw(unc,'seed',1), 1));
        rho   = max(0, min(0.99, getNumericScalar(getFieldOrDefaultRaw(unc,'rho',0.70), 0.70)));
        gamma = max(0, round(getNumericScalar(getFieldOrDefaultRaw(unc,'gamma',6), 6)));

        if ismember(modeStr, ["scenario","stochastic","stocastic"])
            [wt_scen, scenProb] = makePVScenarios(wt_nom, level, S, seed, rho); 
            wt_eff = wt_scen * scenProb(:);

        elseif modeStr == "robust"
            wt_eff = robustPVProfile(wt_nom, level, gamma); 
        else
            wt_eff = wt_nom;
        end

        wt_eff = max(0, min(1, wt_eff));
    end

    
    % ===== Load Uncertainty helpers (Total load only) =====
    
function [total_eff, load_scen, scenProb] = applyTotalLoadUncertainty(total_nom, unc)
        total_nom = total_nom(:);
        N = numel(total_nom);
        load_scen = [];
        scenProb = [];

        if isempty(unc) || ~isfield(unc,'mode')
            total_eff = max(total_nom,0);
            return;
        end

        modeStr = lower(strtrim(string(unc.mode)));
        level = max(0, min(1, getNumericScalar(unc.level, 0.10)));
        S     = max(1, round(getNumericScalar(getFieldOrDefaultRaw(unc,'num_scen',10), 10)));
        seed  = round(getNumericScalar(getFieldOrDefaultRaw(unc,'seed',1), 1));
        rho   = max(0, min(0.99, getNumericScalar(getFieldOrDefaultRaw(unc,'rho',0.70), 0.70)));
        gamma = max(0, round(getNumericScalar(getFieldOrDefaultRaw(unc,'gamma',6), 6)));

        base_safe = max(total_nom, 0);

        if ismember(modeStr, ["scenario","stochastic","stocastic"])
            % --- Stochastic: PV-style (scenarios + expectation), but using lognormal multipliers
            sig = level;  
            [mult_scen, scenProb] = makeLoadMultipliers(base_safe, sig, S, seed, rho);
            load_scen = base_safe .* mult_scen;      % N x S
            total_eff = load_scen * scenProb(:);     % expected load (N x 1)
            meanMult = 1 + level;  
            total_eff = max(total_eff, base_safe * meanMult);

        elseif modeStr == "robust"
            % --- Robust: budgeted worst-case increase on the top-Gamma load steps ---
            mult = robustLoadMultiplier(base_safe, level, gamma);
            total_eff = base_safe .* mult;

        else
            total_eff = base_safe;
        end

        if numel(total_eff) ~= N
            total_eff = base_safe;
        end
    end

    
function [mult_scen, scenProb] = makeLoadMultipliers(base, level, S, seed, rho)
        N = numel(base);
        rng(seed);
        scenProb = (1/S) * ones(S,1);

        level = max(0, min(1, level));
        rho   = max(0, min(0.99, rho));

        mult_scen = ones(N,S);
        sig = level; 
        for s = 1:S
            e = zeros(N,1);
            e(1) = sig*randn();
            for k = 2:N
                e(k) = rho*e(k-1) + sqrt(max(0,1-rho^2))*sig*randn();
            end

            e = max(-3*sig, min(3*sig, e));

            mult = exp(e);     
            mult_scen(:,s) = mult;
        end
    end

function mult = robustLoadMultiplier(base, level, gamma)
        N = numel(base);
        level = max(0, min(1, level));
        gamma = max(0, min(N, round(gamma)));

        mult = ones(N,1);
        if gamma == 0 || level == 0
            return;
        end
        [~, idx] = sort(base,'descend');
        pick = idx(1:gamma);
        mult(pick) = 1 + level;
    end

function [lbl, f] = addNumericRow(g, r, labelText, defaultVal)
        lbl = uilabel(g, 'Text', labelText, 'FontSize', 12);
        lbl.Layout.Row = r;
        lbl.Layout.Column = 1;
        f = uieditfield(g, 'numeric', 'Value', defaultVal);
        f.Layout.Row = r;
        f.Layout.Column = 2;
    end

    function d = buildDialog(titleText, nRows)
        d = uifigure('Name', titleText, 'Position', centerPos(fig, 420, 120 + 48*nRows), 'WindowStyle', 'modal');
        d.Color = [1 1 1];
        g = uigridlayout(d, [nRows+2 2]);
        g.RowHeight = [repmat({34}, 1, nRows), {'1x'}, {38}];
        g.ColumnWidth = {170, '1x'};
        g.Padding = [14 14 14 14];
        g.RowSpacing = 10;
        g.ColumnSpacing = 10;
        setappdata(d,'app_grid',g);
        setappdata(d,'app_save',false);

        btns = uigridlayout(g, [1 2]);
        btns.Layout.Row = nRows+2;
        btns.Layout.Column = [1 2];
        btns.ColumnWidth = {'1x','1x'};
        btns.RowHeight = {38};
        btns.Padding = [0 0 0 0];

        uibutton(btns, 'Text', 'Cancel', 'FontSize', 12, 'ButtonPushedFcn', @(~,~) cancelDlg(d));
        uibutton(btns, 'Text', 'Save',   'FontSize', 12, 'ButtonPushedFcn', @(~,~) saveDlg(d));

        d.CloseRequestFcn = @(~,~) cancelDlg(d);
    end

    function saveDlg(d)
        if isvalid(d)
            setappdata(d,'app_save',true);
            uiresume(d);
        end
    end

    function cancelDlg(d)
        if isvalid(d)
            setappdata(d,'app_save',false);
            uiresume(d);
        end
    end

    function hideParameterControls()
        try
            optimizationParametersPanel.Visible = 'off';
        catch
        end

        try
            resultPanel.Visible = 'off';
        catch
        end

        objs = findall(fig);
        for k = 1:numel(objs)
            o = objs(k);
            try
                if isequal(o.Parent, fig) && isprop(o,'Position')
                    pos = o.Position;
                    if numel(pos) >= 4 && pos(1) >= 230
                        if isa(o,'matlab.ui.control.UIAxes') || isa(o,'matlab.ui.container.GridLayout')
                            continue;
                        end
                        if isprop(o,'Visible')
                            o.Visible = 'off';
                        end
                    end
                end
            catch
            end
        end
    end

    function calculate_and_plot()
      
        
        try
            delete(findall(fig,'Type','legend'));
        catch
        end
        lgd1 = []; lgd2 = []; lgd3 = []; lgd4 = [];

Elec_Price = evalin('base', 'Elec_Price');
        Elec_SellPrice = evalin('base', 'Elec_SellPrice');
        P_PV1 = evalin('base', 'P_PV1');
        P_PV2 = evalin('base', 'P_PV2');
        try
            P_WT1 = evalin('base','P_WT1');
        catch
            P_WT1 = P_PV1; assignin('base','P_WT1',P_WT1);
        end
        try
            P_WT2 = evalin('base','P_WT2');
        catch
            P_WT2 = P_PV2;
            assignin('base','P_WT2',P_WT2);
        end
        % Wind status from GUI checkboxes
        Wind_AC_status = getUIValue(windACStatusField, 0);
        Wind_DC_status = getUIValue(windDCStatusField, 0);
        Grid_status = getUIValue(gridStatusField, 0);
        PV_AC_status = getUIValue(pvACStatusField, 0);
        PV_DC_status = getUIValue(pvDCStatusField, 0);
        Load_AC_status = getUIValue(loadACStatusField, 0);
        Load_DC_status = getUIValue(loadDCStatusField, 0);
        BESS_AC_status = getUIValue(bessACStatusField, 0);
        BESS_DC_status = getUIValue(bessDCStatusField, 0);
        EV_AC_status = getUIValue(evACStatusField, 0);
        EV_DC_status = getUIValue(evDCStatusField, 0);
        ILC_status     = getUIValue(ilcStatusField, 0);
        CDG_status = getUIValue(cdgStatusField, 0);
        MT2_status = getUIValue(mt2StatusField, 0);
        DR_AC_status = getUIValue(drACEnableField, 0);
        DR_DC_status = getUIValue(drDCEnableField, 0);
        if ~exist('drACPctField','var'); drACPctField = []; end
        if ~exist('drDCPctField','var'); drDCPctField = []; end
        if ~exist('drACFlexField','var'); drACFlexField = []; end
        if ~exist('drDCFlexField','var'); drDCFlexField = []; end
        DR_AC_pct = max(0, min(100, getUIValue(drACPctField, 0)));
        DR_DC_pct = max(0, min(100, getUIValue(drDCPctField, 0)));

        
        % --- Load profiles (defaults must match the old shared folder) ---
        haveOldLoads = evalin('base','exist(''P_CL1'',''var'') && exist(''P_NL1'',''var'') && exist(''P_CL2'',''var'') && exist(''P_NL2'',''var'')');
        if haveOldLoads
            P_CL1 = evalin('base','P_CL1');
            P_NL1 = evalin('base','P_NL1');
            P_CL2 = evalin('base','P_CL2');
            P_NL2 = evalin('base','P_NL2');
            P_Load1 = P_CL1 + P_NL1;
            P_Load2 = P_CL2 + P_NL2;
        else
            if evalin('base','exist(''P_Load1'',''var'')')
                P_Load1 = evalin('base','P_Load1');
            else
                P_Load1 = zeros(Num_var,1);
            end
            if evalin('base','exist(''P_Load2'',''var'')')
                P_Load2 = evalin('base','P_Load2');
            else
                P_Load2 = zeros(Num_var,1);
            end
        end

        load_unc = getappdata(fig,'load_unc');
        if isempty(load_unc)
            load_unc = struct();
            load_unc.AC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6,'crit_pct',30);
            load_unc.DC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6,'crit_pct',30);
        end

        % Apply uncertainty
        if haveOldLoads
            [P_CL1_eff, CL1_scen, CL1_prob] = applyTotalLoadUncertainty(P_CL1, load_unc.AC);
            [P_NL1_eff, NL1_scen, NL1_prob] = applyTotalLoadUncertainty(P_NL1, load_unc.AC);
            [P_CL2_eff, CL2_scen, CL2_prob] = applyTotalLoadUncertainty(P_CL2, load_unc.DC);
            [P_NL2_eff, NL2_scen, NL2_prob] = applyTotalLoadUncertainty(P_NL2, load_unc.DC);
            P_Load1_eff = P_CL1_eff + P_NL1_eff;
            P_Load2_eff = P_CL2_eff + P_NL2_eff;

            Load1_scen = []; Load2_scen = []; Load1_prob = []; Load2_prob = [];
            if ~isempty(CL1_scen) && ~isempty(NL1_scen) && isequal(size(CL1_scen), size(NL1_scen))
                Load1_scen = CL1_scen + NL1_scen;
                if isequal(numel(CL1_prob), size(Load1_scen,2))
                    Load1_prob = CL1_prob;
                elseif isequal(numel(NL1_prob), size(Load1_scen,2))
                    Load1_prob = NL1_prob;
                end
            end
            if ~isempty(CL2_scen) && ~isempty(NL2_scen) && isequal(size(CL2_scen), size(NL2_scen))
                Load2_scen = CL2_scen + NL2_scen;
                if isequal(numel(CL2_prob), size(Load2_scen,2))
                    Load2_prob = CL2_prob;
                elseif isequal(numel(NL2_prob), size(Load2_scen,2))
                    Load2_prob = NL2_prob;
                end
            end
        else
            % Total load mode
            [P_Load1_eff, Load1_scen, Load1_prob] = applyTotalLoadUncertainty(P_Load1, load_unc.AC);
            [P_Load2_eff, Load2_scen, Load2_prob] = applyTotalLoadUncertainty(P_Load2, load_unc.DC);
        end

        % Apply Load enable/disable (0=off, 1=on)
        P_Load1_eff = P_Load1_eff .* Load_AC_status;
        P_Load2_eff = P_Load2_eff .* Load_DC_status;
        if haveOldLoads
            P_CL1_eff = P_CL1_eff .* Load_AC_status;
            P_NL1_eff = P_NL1_eff .* Load_AC_status;
            P_CL2_eff = P_CL2_eff .* Load_DC_status;
            P_NL2_eff = P_NL2_eff .* Load_DC_status;
            if ~isempty(Load1_scen), Load1_scen = Load1_scen .* Load_AC_status; end
            if ~isempty(Load2_scen), Load2_scen = Load2_scen .* Load_DC_status; end
        end

        try
            mAC = lower(strtrim(string(getFieldOrDefaultRaw(load_unc.AC,'mode','Deterministic'))));
            mDC = lower(strtrim(string(getFieldOrDefaultRaw(load_unc.DC,'mode','Deterministic'))));
            lvAC = getNumericScalar(getFieldOrDefaultRaw(load_unc.AC,'level',0), 0);
            lvDC = getNumericScalar(getFieldOrDefaultRaw(load_unc.DC,'level',0), 0);
            dAC = max(abs(P_Load1_eff(:) - P_Load1(:)));
            dDC = max(abs(P_Load2_eff(:) - P_Load2(:)));
            fprintf('[LOAD UNC] AC mode=%s level=%.3f max|Δ|=%.6g | DC mode=%s level=%.3f max|Δ|=%.6g\n', ...
                mAC, lvAC, dAC, mDC, lvDC, dDC);
        catch
        end

        try
            assignin('base','P_Load1_eff', P_Load1_eff);
            assignin('base','P_Load2_eff', P_Load2_eff);
            assignin('base','load_unc_used', load_unc);
        catch
        end

        % Split into critical/non-critical
        if haveOldLoads
            P_CL1 = P_CL1_eff;
            P_NL1 = P_NL1_eff;
            P_CL2 = P_CL2_eff;
            P_NL2 = P_NL2_eff;
        else
            crit1_pct = getNumericScalar(getFieldOrDefault(load_unc.AC,'crit_pct',30), 30);
            crit2_pct = getNumericScalar(getFieldOrDefault(load_unc.DC,'crit_pct',30), 30);
            crit1 = max(0, min(1, crit1_pct/100));
            crit2 = max(0, min(1, crit2_pct/100));
            P_CL1 = crit1 .* P_Load1_eff;
            P_NL1 = (1-crit1) .* P_Load1_eff;
            P_CL2 = crit2 .* P_Load2_eff;
            P_NL2 = (1-crit2) .* P_Load2_eff;
        end

        try
            if ~isempty(Load1_scen); assignin('base','P_Load1_scen', Load1_scen); assignin('base','P_Load1_prob', Load1_prob); end
            if ~isempty(Load2_scen); assignin('base','P_Load2_scen', Load2_scen); assignin('base','P_Load2_prob', Load2_prob); end
        catch
        end

% Demand Response (DR): shiftable portion of NON-critical loads (P_NL1 / P_NL2)
        DR_AC_status = getUIValue(drACEnableField, 0);
        DR_DC_status = getUIValue(drDCEnableField, 0);
        DR_AC_pct = max(0, min(100, getUIValue(drACPctField, 0)));
        DR_DC_pct = max(0, min(100, getUIValue(drDCPctField, 0)));

        % Split NON-critical loads into fixed + shiftable (user-defined percentage)
        DR_AC_pct_eff = DR_AC_pct;
        DR_DC_pct_eff = DR_DC_pct;
        if DR_AC_status == 0
            DR_AC_pct_eff = 0;
        end
        if DR_DC_status == 0
            DR_DC_pct_eff = 0;
        end

        NL1_shiftable = (DR_AC_pct_eff/100) * P_NL1;
        NL1_fixed     = P_NL1 - NL1_shiftable;
        NL2_shiftable = (DR_DC_pct_eff/100) * P_NL2;
        NL2_fixed     = P_NL2 - NL2_shiftable;

        
        % Get AC MT values (multi-unit)
        try
            alpha = mean(MT_AC_alpha(:));
            beta  = mean(MT_AC_beta(:));
            gamma = mean(MT_AC_gamma(:));
            M_power = sum(MT_AC_Pmax(:));
        catch
            alpha = alphaField.Value;
            beta  = betaField.Value;
            gamma = gammaField.Value;
            M_power = powerField.Value;
        end
        
        % Get PV/Wind max values
        PV1_Max = PV1maxField.Value;
        PV2_Max = PV2maxField.Value;
        WT1_Max = Wind1maxField.Value;
        WT2_Max = Wind2maxField.Value;
        
        % Get P_conv_max and Eff_conv values
        P_conv_max = PConvMaxField.Value;
        Eff_conv = EffConvField.Value;
        
        % Get AC BESS parameters
        P_BESS1_max = PBESS1MaxField.Value;
        Eff_BESS1 = EffBESS1Field.Value;
        SOC1_max = SOC1MaxField.Value;
        SOC1_min = SOC1MinField.Value;
        CAP1 = CAP1Field.Value;
        
        % Get DC BESS parameters
        P_BESS2_max = PBESS2MaxField.Value;
        Eff_BESS2 = EffBESS2Field.Value;
        SOC2_max = SOC2MaxField.Value;
        SOC2_min = SOC2MinField.Value;
        CAP2 = CAP2Field.Value;

        % Advanced initial conditions / bounds (edited via popups)
        SOC1_init = SOC1InitField.Value;
        SOC2_init = SOC2InitField.Value;

        EV_CAP1 = EV1CapField.Value;
        EV_CAP2 = EV2CapField.Value;

        EV1SOC_init = EV1SOCInitField.Value;
        EV2SOC_init = EV2SOCInitField.Value;

        EV1SOC_min = EV1SOCMinField.Value;
        EV1SOC_max = EV1SOCMaxField.Value;
        EV2SOC_min = EV2SOCMinField.Value;
        EV2SOC_max = EV2SOCMaxField.Value;
        
                % Get AC EV parameters
                P_EV1_max = EV1MaxField.Value;
                Eff_EV1 = EffEV1Field.Value;
                EV1_SOCT = EV1SOCTarField.Value;
                Ta1 = EV1ARRField.Value;
                Td1 = EV1DEPField.Value;

% --- AC EV fleet parameters (N EVs) ---
NEV_AC = max(1, round(getUIValue(NEV_ACField, NEV_AC)));
if exist('EVACTable','var') && ~isempty(EVACTable) && isgraphics(EVACTable)
    D = EVACTable.Data;
    if isempty(D)
        D = defaultEVACData(NEV_AC);
        EVACTable.Data = D;
    end
    % Ensure table has NEV_AC rows
    if size(D,1) < NEV_AC
        D = [D; defaultEVACData(NEV_AC - size(D,1))];
        EVACTable.Data = D;
    elseif size(D,1) > NEV_AC
        D = D(1:NEV_AC,:);
        EVACTable.Data = D;
    end

    % Columns: [Pmax, Eff, Cap, SOC_init, SOC_min, SOC_max, SOC_target, Ta, Td]
    P_EV_AC_max    = D(:,1);
    Eff_EV_AC      = D(:,2);
    EV_AC_CAP      = D(:,3);
    EV_AC_SOC_init = D(:,4);
    EV_AC_SOC_min  = D(:,5);
    EV_AC_SOC_max  = D(:,6);
    EV_AC_SOCT     = D(:,7);
    EV_AC_Ta       = D(:,8);
    EV_AC_Td       = D(:,9);
else
    Eff_EV_AC      = Eff_EV1*ones(NEV_AC,1);
    P_EV_AC_max    = P_EV1_max*ones(NEV_AC,1);
    EV_AC_CAP      = EV_CAP1*ones(NEV_AC,1);
    EV_AC_SOC_init = EV1SOC_init*ones(NEV_AC,1);
    EV_AC_SOC_min  = EV1SOC_min*ones(NEV_AC,1);
    EV_AC_SOC_max  = EV1SOC_max*ones(NEV_AC,1);
    EV_AC_SOCT     = EV1_SOCT*ones(NEV_AC,1);
    EV_AC_Ta       = Ta1*ones(NEV_AC,1);
    EV_AC_Td       = Td1*ones(NEV_AC,1);
end

        
                
% --- DC EV fleet parameters (N EVs) ---
NEV_DC = max(1, round(getUIValue(NEV_DCField, NEV_DC)));
if exist('EVDCTable','var') && ~isempty(EVDCTable) && isgraphics(EVDCTable)
    D2 = EVDCTable.Data;
    if isempty(D2)
        D2 = defaultEVDCData(NEV_DC);
        EVDCTable.Data = D2;
    end
    if size(D2,1) < NEV_DC
        D2 = [D2; defaultEVDCData(NEV_DC - size(D2,1))];
        EVDCTable.Data = D2;
    elseif size(D2,1) > NEV_DC
        D2 = D2(1:NEV_DC,:);
        EVDCTable.Data = D2;
    end

    if istable(D2), D2 = table2cell(D2); end
    if isnumeric(D2)
        M2 = D2;
    else
        if ~iscell(D2), D2 = num2cell(D2); end
        if size(D2,1) < NEV_DC, D2(end+1:NEV_DC,1:size(D2,2)) = {[]}; end
        if size(D2,1) > NEV_DC, D2 = D2(1:NEV_DC,:); end
        if size(D2,2) < 9, D2(:,end+1:9) = {[]}; end
        if size(D2,2) > 9, D2 = D2(:,1:9); end
        M2 = zeros(NEV_DC,9);
        for rr = 1:NEV_DC
            for cc = 1:9
                vv = D2{rr,cc};
                if isempty(vv)
                    M2(rr,cc) = 0;
                elseif isnumeric(vv)
                    M2(rr,cc) = vv;
                elseif ischar(vv) || isstring(vv)
                    tmp = str2double(vv);
                    if isnan(tmp), tmp = 0; end
                    M2(rr,cc) = tmp;
                else
                    try
                        tmp = double(vv);
                        if isempty(tmp) || ~isscalar(tmp) || isnan(tmp), tmp = 0; end
                        M2(rr,cc) = tmp;
                    catch
                        M2(rr,cc) = 0;
                    end
                end
            end
        end
    end
    D2 = M2;

    P_EV_DC_max    = D2(:,1);
    Eff_EV_DC      = D2(:,2);
    EV_DC_CAP      = D2(:,3);
    EV_DC_SOC_init = D2(:,4);
    EV_DC_SOC_min  = D2(:,5);
    EV_DC_SOC_max  = D2(:,6);
    EV_DC_SOCT     = D2(:,7);
    EV_DC_Ta       = D2(:,8);
    EV_DC_Td       = D2(:,9);
else
    % Fallback: replicate current single DC EV settings (model parameters)
    P_EV_DC_max    = P_EV2_max*ones(NEV_DC,1);
    Eff_EV_DC      = Eff_EV2*ones(NEV_DC,1);
    EV_DC_CAP      = EV_CAP2*ones(NEV_DC,1);
    EV_DC_SOC_init = EV2SOC_init*ones(NEV_DC,1);
    EV_DC_SOC_min  = EV2SOC_min*ones(NEV_DC,1);
    EV_DC_SOC_max  = EV2SOC_max*ones(NEV_DC,1);
    EV_DC_SOCT     = EV2_SOCT*ones(NEV_DC,1);
    EV_DC_Ta       = Ta2*ones(NEV_DC,1);
    EV_DC_Td       = Td2*ones(NEV_DC,1);
end

P_EV2_max = P_EV_DC_max(1);
Eff_EV2   = Eff_EV_DC(1);
EV2_SOCT  = EV_DC_SOCT(1);
Ta2       = EV_DC_Ta(1);
Td2       = EV_DC_Td(1);
EV_CAP2   = EV_DC_CAP(1);
EV2SOC_init = EV_DC_SOC_init(1);
EV2SOC_min  = EV_DC_SOC_min(1);
EV2SOC_max  = EV_DC_SOC_max(1);

% Get Maximum Grid Power
        P_grid_max = PGridMaxField.Value;
        
        pv_unc = getappdata(fig,'pv_unc');
        if isempty(pv_unc)
            pv_unc = struct();
            pv_unc.AC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6);
            pv_unc.DC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6);
        end

        [P_PV1_eff, PV1_scen, PV1_prob] = applyPVUncertainty(P_PV1, pv_unc.AC);
        [P_PV2_eff, PV2_scen, PV2_prob] = applyPVUncertainty(P_PV2, pv_unc.DC);

        try
            if ~isempty(PV1_scen); assignin('base','P_PV1_scen', PV1_scen); assignin('base','P_PV1_prob', PV1_prob); end
            if ~isempty(PV2_scen); assignin('base','P_PV2_scen', PV2_scen); assignin('base','P_PV2_prob', PV2_prob); end
        catch
        end

        
        % ----- WT uncertainty (WT only) -----
        wt_unc = getappdata(fig,'wt_unc');
        if isempty(wt_unc)
            wt_unc = struct();
            wt_unc.AC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6);
            wt_unc.DC = struct('mode','Deterministic','level',0.10,'num_scen',10,'seed',1,'rho',0.70,'gamma',6);
        end

        [P_WT1_eff, WT1_scen, WT1_prob] = applyWTUncertainty(P_WT1, wt_unc.AC);
        [P_WT2_eff, WT2_scen, WT2_prob] = applyWTUncertainty(P_WT2, wt_unc.DC);

        % Optional: export WT scenario matrices to base workspace for inspection
        try
            if ~isempty(WT1_scen)
                assignin('base','P_WT1_scen', WT1_scen);
                assignin('base','P_WT1_prob', WT1_prob);
            else
                evalin('base','if exist(''P_WT1_scen'',''var''), clear P_WT1_scen; end');
                evalin('base','if exist(''P_WT1_prob'',''var''), clear P_WT1_prob; end');
            end
            if ~isempty(WT2_scen)
                assignin('base','P_WT2_scen', WT2_scen);
                assignin('base','P_WT2_prob', WT2_prob);
            else
                evalin('base','if exist(''P_WT2_scen'',''var''), clear P_WT2_scen; end');
                evalin('base','if exist(''P_WT2_prob'',''var''), clear P_WT2_prob; end');
            end
        catch
        end


        dt = 1/4; 

        P_PV1 = PV_AC_Module(Num_var, P_PV1_eff, PV1_Max, PV_AC_status);
        P_PV2 = PV_DC_Module(Num_var, P_PV2_eff, PV2_Max, PV_DC_status);
        P_WT1 = Wind_AC_Module(Num_var, P_WT1_eff, WT1_Max, Wind_AC_status);
        P_WT2 = Wind_DC_Module(Num_var, P_WT2_eff, WT2_Max, Wind_DC_status);
        [BAC_lb, BAC_ub, BAC_A, BAC_b, SOC1_init] = BESS_AC_Module(dt, Num_var, Eff_BESS1, P_BESS1_max,  CAP1, SOC1_init, SOC1_min, SOC1_max, BESS_AC_status);
        [BDC_lb, BDC_ub, BDC_A, BDC_b, SOC2_init] = BESS_DC_Module(dt, Num_var, Eff_BESS2, P_BESS2_max, CAP2, SOC2_init, SOC2_min, SOC2_max, BESS_DC_status);
        NB_GRID = 10; NB_CDG = 11; NB_BAC = 2; NB_BDC = 2; NB_ILC = 2;
        NB_EAC = 2*NEV_AC;
        NB_EDC = 2*NEV_DC;
        NB_EAC = 2*NEV_AC;
        NB_BASE = NB_GRID + NB_CDG + NB_BAC + NB_BDC + NB_EAC + NB_EDC + NB_ILC; % base before MT2
        NB_MT = 11; NB_DR = 6;
        EV_AC_status_vec = EV_AC_status*ones(NEV_AC,1);
        EAC_lb = []; EAC_ub = []; EAC_A = []; EAC_b = []; AC_EVP = zeros(Num_var, NEV_AC);
        for evIdx = 1:NEV_AC
            preBlocks = 25 + 2*(evIdx-1);
            postBlocks = NB_BASE - (preBlocks + 2);
            [lb_i, ub_i, A_i, b_i, socInit_i, EVP_i] = EV_AC_Module(dt, Num_var, Eff_EV_AC(evIdx), P_EV_AC_max(evIdx), EV_AC_CAP(evIdx), EV_AC_SOC_init(evIdx), EV_AC_SOC_min(evIdx), EV_AC_SOC_max(evIdx), EV_AC_Ta(evIdx), EV_AC_Td(evIdx), EV_AC_SOCT(evIdx), Grid_status, EV_AC_status_vec(evIdx), preBlocks, postBlocks);
            EAC_lb = [EAC_lb; lb_i];
            EAC_ub = [EAC_ub; ub_i];
            EAC_A  = [EAC_A;  A_i];
            EAC_b  = [EAC_b;  b_i];
            EV_AC_SOC_init(evIdx) = socInit_i;
            AC_EVP(:,evIdx) = EVP_i;
        end

        EV_DC_status_vec = EV_DC_status*ones(NEV_DC,1);
        EDC_lb = []; EDC_ub = []; EDC_A = []; EDC_b = []; DC_EVP = zeros(Num_var, NEV_DC);
        for evIdx = 1:NEV_DC
            preBlocks  = 25 + 2*NEV_AC + 2*(evIdx-1);
            postBlocks = NB_BASE - (preBlocks + 2);
            [lb_i, ub_i, A_i, b_i, socInit_i, EVP_i] = EV_DC_Module(dt, Num_var, Eff_EV_DC(evIdx), P_EV_DC_max(evIdx), ...
                EV_DC_CAP(evIdx), EV_DC_SOC_init(evIdx), EV_DC_SOC_min(evIdx), EV_DC_SOC_max(evIdx), ...
                EV_DC_Ta(evIdx), EV_DC_Td(evIdx), EV_DC_SOCT(evIdx), Grid_status, ILC_status, EV_DC_status_vec(evIdx), preBlocks, postBlocks);
            EDC_lb = [EDC_lb; lb_i]; 
            EDC_ub = [EDC_ub; ub_i]; 
            EDC_A  = [EDC_A;  A_i];  
            EDC_b  = [EDC_b;  b_i];  
            EV_DC_SOC_init(evIdx) = socInit_i;
            DC_EVP(:,evIdx) = EVP_i;
        end
        EV2SOC_init = EV_DC_SOC_init(1);

        [G_lb, G_ub] = Grid_Module(Num_var, P_grid_max, P_CL1, P_NL1, P_CL2, P_NL2, P_PV1, P_PV2, P_WT1, P_WT2, Grid_status, ILC_status);
        [S_diesel, C_lb, C_ub, C_A, C_b] = CDG_Module(alpha, beta, gamma, M_power, Num_var, CDG_status);
                [S_mt2, C2_lb, C2_ub, C2_A, C2_b] = MT_DC_Module(alpha2, beta2, gamma2, M_power2, Num_var, MT2_status, NB_BASE);

        [I_lb, I_ub] = ILC_Module(Num_var, Eff_conv, P_conv_max, ILC_status);


        if ~exist('drACFlexField','var');      drACFlexField = [];      end
        if ~exist('drACLambdaField','var');    drACLambdaField = [];    end
        if ~exist('drACRampFracField','var');  drACRampFracField = [];  end
        if ~exist('drDCFlexField','var');      drDCFlexField = [];      end
        if ~exist('drDCLambdaField','var');    drDCLambdaField = [];    end
        if ~exist('drDCRampFracField','var');  drDCRampFracField = [];  end

        DR_flex_AC     = max(0, min(2,   getUIValue(drACFlexField, 1)));
        lambdaDR_AC    = max(0,          getUIValue(drACLambdaField, 0));
        DR_rampFrac_AC = max(0, min(1,   getUIValue(drACRampFracField, 0)));
        DR_flex_DC     = max(0, min(2,   getUIValue(drDCFlexField, 1)));
        lambdaDR_DC    = max(0,          getUIValue(drDCLambdaField, 0));
        DR_rampFrac_DC = max(0, min(1,   getUIValue(drDCRampFracField, 0)));

        if DR_AC_status == 0 || all(NL1_shiftable == 0)
            DR_flex_AC = 0; lambdaDR_AC = 0; DR_rampFrac_AC = 0;
        end
        if DR_DC_status == 0 || all(NL2_shiftable == 0)
            DR_flex_DC = 0; lambdaDR_DC = 0; DR_rampFrac_DC = 0;
        end

        % Bounds for DR scheduled shiftable profiles
        if DR_AC_status == 0 || all(NL1_shiftable == 0)
            DR_NL1_lb = NL1_shiftable;
            DR_NL1_ub = NL1_shiftable;
        else
            DR_NL1_lb = max(0, (1-DR_flex_AC) * NL1_shiftable);
            DR_NL1_ub = (1+DR_flex_AC) * NL1_shiftable + 1e-9;
        end

        if DR_DC_status == 0 || all(NL2_shiftable == 0)
            DR_NL2_lb = NL2_shiftable;
            DR_NL2_ub = NL2_shiftable;
        else
            DR_NL2_lb = max(0, (1-DR_flex_DC) * NL2_shiftable);
            DR_NL2_ub = (1+DR_flex_DC) * NL2_shiftable + 1e-9;
        end

        if DR_AC_status == 0 || all(NL1_shiftable == 0)
            dev1_ub = zeros(Num_var,1);
        else
            dev1_ub = DR_flex_AC * NL1_shiftable + 1e-9;
        end
        if DR_DC_status == 0 || all(NL2_shiftable == 0)
            dev2_ub = zeros(Num_var,1);
        else
            dev2_ub = DR_flex_DC * NL2_shiftable + 1e-9;
        end

        intcon = 1 + Num_var * 3 : Num_var * 4; 
        
	        DR_DEV_lb = zeros(Num_var*4, 1);
	        DR_DEV_ub = [dev1_ub; dev1_ub; dev2_ub; dev2_ub];
	        
	        % Lower Bounds
	        lb = [G_lb; C_lb; BAC_lb; BDC_lb; EAC_lb; EDC_lb; I_lb; C2_lb; DR_NL1_lb; DR_NL2_lb; DR_DEV_lb];
	        
	        % Upper Bounds
	        ub = [G_ub; C_ub; BAC_ub; BDC_ub; EAC_ub; EDC_ub; I_ub; C2_ub; DR_NL1_ub; DR_NL2_ub; DR_DEV_ub];
        nX = length(lb);
        f = zeros(nX,1);
        f(1:Num_var)                         = dt * Elec_Price(:);      % Grid buy
        f(Num_var+1:2*Num_var)               = dt * Elec_SellPrice(:);  % Grid sell
        f(2*Num_var+1:3*Num_var)             = dt * reshape(Pen_P_CL1,[],1);       % Shed CL1
        f(3*Num_var+1:4*Num_var)             = dt * reshape(Pen_P_NL1,[],1);       % Shed NL1
        f(4*Num_var+1:5*Num_var)             = dt * reshape(Pen_P_CL2,[],1);       % Shed CL2
        f(5*Num_var+1:6*Num_var)             = dt * reshape(Pen_P_NL2,[],1);       % Shed NL2
        f(6*Num_var+1:7*Num_var)             = dt * reshape(Pen_PV1,[],1);         % Curtail PV1
        f(7*Num_var+1:8*Num_var)             = dt * reshape(Pen_PV2,[],1);         % Curtail PV2
        f(8*Num_var+1:9*Num_var)             = dt * reshape(Pen_Wind1,[],1);       % Curtail Wind1
        f(9*Num_var+1:10*Num_var)            = dt * reshape(Pen_Wind2,[],1);       % Curtail Wind2

        % ---- Diesel (CDG) piecewise cost (C_lb block follows Grid block) ----
        try
            offC = length(G_lb); 
            try
                f(offC + (1:Num_var)) = dt * alpha * ones(Num_var,1);
            catch
            end
            for jj = 1:10
                b = 1 + jj;
                idx1 = offC + (b-1)*Num_var + 1;
                idx2 = offC + b*Num_var;
                f(idx1:idx2) = dt * S_diesel(jj) * ones(Num_var,1);
            end
        catch
        end

        % ---- MT2 (DC microturbine) piecewise cost (C2_lb follows ILC block) ----
        try
            offC2 = length(G_lb) + length(C_lb) + length(BAC_lb) + length(BDC_lb) + length(EAC_lb) + length(EDC_lb) + length(I_lb);
            try
                f(offC2 + (1:Num_var)) = dt * alpha2 * ones(Num_var,1);
            catch
            end
            for jj = 1:10
                b = 1 + jj; 
                idx1 = offC2 + (b-1)*Num_var + 1;
                idx2 = offC2 + b*Num_var;
                f(idx1:idx2) = dt * S_mt2(jj) * ones(Num_var,1);
            end
        catch
        end

        % DR deviation penalties (last 4 Num_var blocks: DEV1+/DEV1-/DEV2+/DEV2-)
        if nX >= 4*Num_var
            f(end-4*Num_var+1:end-2*Num_var) = dt * reshape(lambdaDR_AC,[],1);     % DEV1_POS & DEV1_NEG
            f(end-2*Num_var+1:end)           = dt * reshape(lambdaDR_DC,[],1);     % DEV2_POS & DEV2_NEG
        end
        
        % Inequality Constraints

        baseCols = length(lb) - Num_var*NB_DR;  % columns excluding appended DR blocks
        targetIneqCols = baseCols;
        padCols = @(M,n) [ M(:, 1:min(size(M,2),n)), zeros(size(M,1), max(0, n - size(M,2))) ];
        BAC_A = padCols(BAC_A, targetIneqCols);
        BDC_A = padCols(BDC_A, targetIneqCols);
        EAC_A = padCols(EAC_A, targetIneqCols);
        EDC_A = padCols(EDC_A, targetIneqCols);
        C_A   = padCols(C_A,   targetIneqCols);
        C2_A  = padCols(C2_A,  targetIneqCols);
        
        A = [BAC_A; BDC_A; EAC_A; EDC_A; C_A; C2_A];
        b = [BAC_b; BDC_b; EAC_b; EDC_b; C_b; C2_b];

        A = [A, zeros(size(A,1), length(lb) - size(A,2))];  % pad to full decision size
        
        
% Equality Constraints
lenG   = length(G_lb);
lenC   = length(C_lb);
lenBAC = length(BAC_lb);
lenBDC = length(BDC_lb);
lenEAC = length(EAC_lb);
lenEDC = length(EDC_lb);
lenI   = length(I_lb);
lenC2  = length(C2_lb);

baseCols = lenG + lenC + lenBAC + lenBDC + lenEAC + lenEDC + lenI + lenC2;

Aeq1 = zeros(Num_var, baseCols); % AC balance
Aeq2 = zeros(Num_var, baseCols); % DC balance

blk = @(off,b) (off + (b-1)*Num_var + 1) : (off + b*Num_var);

offG   = 0;
offC   = lenG;
offBAC = offC + lenC;
offBDC = offBAC + lenBAC;
offEAC = offBDC + lenBDC;
offEDC = offEAC + lenEAC;
offI   = offEDC + lenEDC;
offC2  = offI + lenI;

% --- Grid terms (common) ---
Aeq1(:, blk(offG,1)) = eye(Num_var); % Grid buy
Aeq1(:, blk(offG,2)) = eye(Num_var); % Grid sell (negative variable)
Aeq2(:, blk(offG,1)) = zeros(Num_var); % Grid buy only on AC side
Aeq2(:, blk(offG,2)) = zeros(Num_var); % Grid sell only on AC side

% Load shedding contributes positively to the balance (reduces served load)
Aeq1(:, blk(offG,3)) = eye(Num_var);
Aeq1(:, blk(offG,4)) = eye(Num_var);
Aeq2(:, blk(offG,5)) = eye(Num_var);
Aeq2(:, blk(offG,6)) = eye(Num_var);

% Curtailment reduces the effective renewable injection.
Aeq1(:, blk(offG,7)) = -eye(Num_var);  % AC PV curtail
Aeq2(:, blk(offG,8)) = -eye(Num_var);  % DC PV curtail
Aeq1(:, blk(offG,9)) = -eye(Num_var);  % AC Wind curtail
Aeq2(:, blk(offG,10))= -eye(Num_var);  % DC Wind curtail

% --- CDG (diesel generator on AC) ---
for jj = 2:11
    Aeq1(:, blk(offC,jj)) = eye(Num_var);
end

% --- BESS ---
Aeq1(:, blk(offBAC,1)) = eye(Num_var);
Aeq1(:, blk(offBAC,2)) = eye(Num_var);
Aeq2(:, blk(offBDC,1)) = eye(Num_var);
Aeq2(:, blk(offBDC,2)) = eye(Num_var);

% --- EV fleets ---
% Each EV adds 2 blocks: [P_dis ; P_chg] with P_chg <= 0.
for bb = 1:(2*NEV_AC)
    Aeq1(:, blk(offEAC,bb)) = eye(Num_var);
end
for bb = 1:(2*NEV_DC)
    Aeq2(:, blk(offEDC,bb)) = eye(Num_var);
end

% --- Interlinking converter (AC/DC) ---
% Two blocks: [P_conv1 (>=0) ; P_conv2 (<=0)].
Eff_conv_safe = max(eps, Eff_conv);
Aeq1(:, blk(offI,1)) = -eye(Num_var);             % P_ac2dc (AC -> DC), AC loses
Aeq1(:, blk(offI,2)) = -(Eff_conv_safe)   * eye(Num_var); % P_dc2ac encoded as negative var, AC receives
Aeq2(:, blk(offI,1)) = +(Eff_conv_safe) * eye(Num_var); % P_ac2dc, DC receives after eff
Aeq2(:, blk(offI,2)) = +eye(Num_var);             % P_dc2ac (negative var), DC loses

% --- DC Microturbine (MT2) ---
for jj = 2:11
    Aeq2(:, blk(offC2,jj)) = eye(Num_var);
end

beq1 = P_CL1 + NL1_fixed - P_PV1 - (Wind_AC_status)*P_WT1;
beq2 = P_CL2 + NL2_fixed - P_PV2 - (Wind_DC_status)*P_WT2;
	        Aeq1 = [Aeq1, -eye(Num_var), zeros(Num_var, Num_var), zeros(Num_var, Num_var*4)];
	        Aeq2 = [Aeq2, zeros(Num_var, Num_var), -eye(Num_var), zeros(Num_var, Num_var*4)];
        Aeq = [Aeq1; Aeq2];
        beq = [beq1; beq2];
nbDRblocks = NB_DR; 
totalVars = size(Aeq,2);
idxDR0 = totalVars - Num_var*nbDRblocks + 1;  
idxDR0 = max(1, idxDR0);

Aeq_DR1 = zeros(1, totalVars);
Aeq_DR1(idxDR0 : min(totalVars, idxDR0+Num_var-1)) = 1;  % sum of P_DR_NL1

Aeq_DR2 = zeros(1, totalVars);
Aeq_DR2((idxDR0+Num_var) : min(totalVars, idxDR0+2*Num_var-1)) = 1;  % sum of P_DR_NL2

if size(Aeq_DR1,2) < size(Aeq,2)
    Aeq_DR1 = [Aeq_DR1 zeros(1, size(Aeq,2)-size(Aeq_DR1,2))];
elseif size(Aeq_DR1,2) > size(Aeq,2)
    Aeq = [Aeq zeros(size(Aeq,1), size(Aeq_DR1,2)-size(Aeq,2))];
end
if size(Aeq_DR2,2) < size(Aeq,2)
    Aeq_DR2 = [Aeq_DR2 zeros(1, size(Aeq,2)-size(Aeq_DR2,2))];
elseif size(Aeq_DR2,2) > size(Aeq,2)
    Aeq = [Aeq zeros(size(Aeq,1), size(Aeq_DR2,2)-size(Aeq,2))];
end

        Aeq = [Aeq; Aeq_DR1; Aeq_DR2];
        beq = [beq; sum(NL1_shiftable); sum(NL2_shiftable)];
	        
	        totalVars = size(Aeq,2);
	        baseCols  = totalVars - Num_var*NB_DR;
	        idxDR0    = baseCols + 1;  
	        
	        Aeq_dev1 = zeros(Num_var, totalVars);
	        Aeq_dev1(:, idxDR0                 : idxDR0+Num_var-1)       =  eye(Num_var);  % P_DR_NL1
	        Aeq_dev1(:, idxDR0+2*Num_var       : idxDR0+3*Num_var-1)     = -eye(Num_var);  % DEV1_POS
	        Aeq_dev1(:, idxDR0+3*Num_var       : idxDR0+4*Num_var-1)     =  eye(Num_var);  % DEV1_NEG
	        
	        Aeq_dev2 = zeros(Num_var, totalVars);
	        Aeq_dev2(:, idxDR0+Num_var         : idxDR0+2*Num_var-1)     =  eye(Num_var);  % P_DR_NL2
	        Aeq_dev2(:, idxDR0+4*Num_var       : idxDR0+5*Num_var-1)     = -eye(Num_var);  % DEV2_POS
	        Aeq_dev2(:, idxDR0+5*Num_var       : idxDR0+6*Num_var-1)     =  eye(Num_var);  % DEV2_NEG
	        Aeq = [Aeq; Aeq_dev1; Aeq_dev2];
	        beq = [beq; NL1_shiftable; NL2_shiftable];
	        
	        Delta1 = 0; Delta2 = 0;
	        if (DR_AC_status ~= 0) && any(NL1_shiftable > 0)
	            Delta1 = DR_rampFrac_AC * max(NL1_shiftable + eps);
	        end
	        if (DR_DC_status ~= 0) && any(NL2_shiftable > 0)
	            Delta2 = DR_rampFrac_DC * max(NL2_shiftable + eps);
	        end
	        D = diff(eye(Num_var),1,1); 
	        if Delta1 > 0
	            A_r1 = [zeros(Num_var-1, Num_var*(NB_BASE+NB_MT+2)),  D, -D, zeros(Num_var-1, Num_var*2)];
	            A = [A; A_r1; -A_r1];
	            b = [b; Delta1*ones(Num_var-1,1); Delta1*ones(Num_var-1,1)];
	        end
	        if Delta2 > 0
	            A_r2 = [zeros(Num_var-1, Num_var*(NB_BASE+NB_MT+4)),  D, -D];
	            A = [A; A_r2; -A_r2];
	            b = [b; Delta2*ones(Num_var-1,1); Delta2*ones(Num_var-1,1)];
	        end
        
        % Solve Mixed-integer Linear Programming
        nX = length(lb);
        f = f(:);
        if length(f) < nX, f(end+1:nX,1) = 0; end
        if length(f) > nX, f = f(1:nX); end
        if size(A,2) < nX,   A   = [A   zeros(size(A,1),   nX-size(A,2))]; end
        if size(A,2) > nX,   A   = A(:,1:nX); end
        if size(Aeq,2) < nX, Aeq = [Aeq zeros(size(Aeq,1), nX-size(Aeq,2))]; end
        if size(Aeq,2) > nX, Aeq = Aeq(:,1:nX); end
        if length(lb) < nX,  lb  = [lb; -inf(nX-length(lb),1)]; end
        if length(ub) < nX,  ub  = [ub;  inf(nX-length(ub),1)]; end
        if length(lb) > nX,  lb  = lb(1:nX); end
        if length(ub) > nX,  ub  = ub(1:nX); end
        
        
[x,fval,exitflag,output] = linprog(f, A, b, Aeq, beq, lb, ub);
        if isempty(x) || exitflag <= 0
            msg = 'No feasible solution found. DR constraints may be too tight for the selected settings.';
            try
                if exist('output','var') && isfield(output,'message'); msg = output.message; end
            catch
            end
            try
                uialert(fig, msg, 'Optimization failed');
            catch
                warning(msg);
            end
            return;
        end

        
        % Extract solution variables
        P_grid = x(1 : Num_var) + x(1 + Num_var : Num_var*2);
        P_Shed_CL1 = x(1 + Num_var*2 : Num_var*3);
        P_Shed_NL1 = x(1 + Num_var*3 : Num_var*4);
        P_Shed_CL2 = x(1 + Num_var*4 : Num_var*5);
        P_Shed_NL2 = x(1 + Num_var*5 : Num_var*NB_DR);
        P_Cur_PV1 = x(1 + Num_var*6 : Num_var*7);
        P_Cur_PV2 = x(1 + Num_var*7 : Num_var*8);
        P_Cur_Wind1 = x(1 + Num_var*8 : Num_var*9);
        P_Cur_Wind2 = x(1 + Num_var*9 : Num_var*10);

        % WT alias for wind curtailment (for plotting/labels)
        P_Cur_WT1 = P_Cur_Wind1;
        P_Cur_WT2 = P_Cur_Wind2;

        % DR scheduled non-critical loads
        idxBaseMT = Num_var*(NB_BASE+NB_MT);
        idxDR0    = idxBaseMT + 1; % first DR variable index in x
        P_DR_NL1  = x(idxDR0 : idxDR0 + Num_var - 1);
        P_DR_NL2  = x(idxDR0 + Num_var : idxDR0 + 2*Num_var - 1);

        P_DR_NL1 = reshape(P_DR_NL1, [], 1);
        P_DR_NL2 = reshape(P_DR_NL2, [], 1);
        if length(P_DR_NL1) < Num_var, P_DR_NL1(end+1:Num_var,1) = 0; else, P_DR_NL1 = P_DR_NL1(1:Num_var); end
        if length(P_DR_NL2) < Num_var, P_DR_NL2(end+1:Num_var,1) = 0; else, P_DR_NL2 = P_DR_NL2(1:Num_var); end

% Served non-critical loads after DR (fixed + scheduled shiftable)
        NL1_fixed = reshape(NL1_fixed, [], 1);
        NL2_fixed = reshape(NL2_fixed, [], 1);
        if length(NL1_fixed) < Num_var, NL1_fixed(end+1:Num_var,1) = 0; else, NL1_fixed = NL1_fixed(1:Num_var); end
        if length(NL2_fixed) < Num_var, NL2_fixed(end+1:Num_var,1) = 0; else, NL2_fixed = NL2_fixed(1:Num_var); end
        P_NL1_served = NL1_fixed + P_DR_NL1;
        P_NL2_served = NL2_fixed + P_DR_NL2;

% AC CDG power: sum only piecewise generation blocks (exclude commitment block u)
        P_diesel = zeros(Num_var,1);
        for k = 1:10
            b = 10 + k; % blocks 11..20 are the 10 AC CDG piecewise power blocks
            P_diesel = P_diesel + x(1 + Num_var*b : Num_var*(b+1));
        end
        % Sum only the 10 piecewise generation blocks; exclude commitment block u
        P_MT2 = zeros(Num_var,1);
        for k = 1:10
            b = NB_BASE + (k-1);
            P_MT2 = P_MT2 + x(1 + Num_var*b : Num_var*(b+1));
        end

        try
            xBase = x(1:baseCols);
            EqRes = Aeq * xBase - beq;
            EqRes_AC = EqRes(1:Num_var);
            EqRes_DC = EqRes(Num_var+1:2*Num_var);
        catch
            EqRes_AC = zeros(Num_var,1);
            EqRes_DC = zeros(Num_var,1);
        end

        P_BESS1dis = x(1 + Num_var*21 : Num_var*22);
        P_BESS1chg = x(1 + Num_var*22 : Num_var*23);
        P_BESS1 = P_BESS1dis + P_BESS1chg;
        P_BESS2dis = x(1 + Num_var*23 : Num_var*24);
        P_BESS2chg = x(1 + Num_var*24 : Num_var*25);
        P_BESS2 = P_BESS2dis + P_BESS2chg;
        % --- EVs (AC side: NEV_AC) ---
        P_EV_AC_dis = zeros(Num_var, NEV_AC);
        P_EV_AC_chg = zeros(Num_var, NEV_AC);
        P_EV_AC     = zeros(Num_var, NEV_AC);
        EV_AC_SOC   = zeros(Num_var, NEV_AC);
        for evIdx = 1:NEV_AC
            b0 = 25 + 2*(evIdx-1);
            P_EV_AC_dis(:,evIdx) = x(1 + Num_var*b0 : Num_var*(b0+1));
            P_EV_AC_chg(:,evIdx) = x(1 + Num_var*(b0+1) : Num_var*(b0+2));
            P_EV_AC(:,evIdx) = P_EV_AC_dis(:,evIdx) + P_EV_AC_chg(:,evIdx);
			Ta_i = max(1, min(Num_var, round(EV_AC_Ta(evIdx)./dt)));
			Td_i = max(1, min(Num_var, round(EV_AC_Td(evIdx)./dt)));
			if Td_i < Ta_i, Td_i = Num_var; end
			soc = zeros(Num_var,1);
			if EV_AC_status_vec(evIdx) ~= 0
				% P_dis >= 0, P_chg <= 0  (so charging increases SOC through the minus sign)
				chg = P_EV_AC_chg(:,evIdx);
				dis = P_EV_AC_dis(:,evIdx);
				idx = Ta_i:Td_i;
				soc(idx) = EV_AC_SOC_init(evIdx) ...
					- (dt*100/EV_AC_CAP(evIdx))*( cumsum(dis(idx))/Eff_EV_AC(evIdx) + cumsum(chg(idx))*Eff_EV_AC(evIdx) );
			end
			EV_AC_SOC(:,evIdx) = soc;
        end
        P_EV1  = P_EV_AC(:,1);
        EV1SOC = EV_AC_SOC(:,1);

        % --- DC EVs (fleet) ---
        bE2_base = 25 + 2*NEV_AC;
        P_EV_DC_dis = zeros(Num_var, NEV_DC);
        P_EV_DC_chg = zeros(Num_var, NEV_DC);
        P_EV_DC     = zeros(Num_var, NEV_DC);
        EV_DC_SOC   = zeros(Num_var, NEV_DC);

        for evIdx = 1:NEV_DC
            b0 = bE2_base + 2*(evIdx-1);
            P_EV_DC_dis(:,evIdx) = x(1 + Num_var*b0 : Num_var*(b0+1));
            P_EV_DC_chg(:,evIdx) = x(1 + Num_var*(b0+1) : Num_var*(b0+2));
            P_EV_DC(:,evIdx)     = P_EV_DC_dis(:,evIdx) + P_EV_DC_chg(:,evIdx);

			% Compute SOC like AC: SOC = 0 when EV not present; evolve only during presence
			Ta_i = max(1, min(Num_var, round(EV_DC_Ta(evIdx)./dt)));
			Td_i = max(1, min(Num_var, round(EV_DC_Td(evIdx)./dt)));
			if Td_i < Ta_i, Td_i = Num_var; end
			soc = zeros(Num_var,1);
			if EV_DC_status_vec(evIdx) ~= 0
				chg = P_EV_DC_chg(:,evIdx);  % <=0
				dis = P_EV_DC_dis(:,evIdx);  % >=0
				idx = Ta_i:Td_i;
				soc(idx) = EV_DC_SOC_init(evIdx) ...
					- (dt*100/EV_DC_CAP(evIdx))*( cumsum(dis(idx))/Eff_EV_DC(evIdx) + cumsum(chg(idx))*Eff_EV_DC(evIdx) );
			end
			EV_DC_SOC(:,evIdx) = soc;
        end
        P_EV2dis = P_EV_DC_dis(:,1);
        P_EV2chg = P_EV_DC_chg(:,1);
        P_EV2    = P_EV_DC(:,1);
        EV2SOC   = EV_DC_SOC(:,1);

        % --- Converter / ILC ---
        bConv = bE2_base + 2*NEV_DC;
        P_conv_pos = x(1 + Num_var*bConv : Num_var*(bConv+1));
        P_conv_neg = x(1 + Num_var*(bConv+1) : Num_var*(bConv+2));
        P_conv = P_conv_pos + P_conv_neg;
        SOC1 = SOC1_init*ones(Num_var,1) - (dt*100/CAP1)*tril(ones(Num_var))*P_BESS1dis/Eff_BESS1 - (dt*100/CAP1)*tril(ones(Num_var))*P_BESS1chg*Eff_BESS1;
        SOC2 = SOC2_init*ones(Num_var,1) - (dt*100/CAP2)*tril(ones(Num_var))*P_BESS2dis/Eff_BESS2 - (dt*100/CAP2)*tril(ones(Num_var))*P_BESS2chg*Eff_BESS2;
        EV1SOC = EV1SOC.*AC_EVP;
        EV_DC_SOC = EV_DC_SOC.*DC_EVP;
        EV2SOC = EV_DC_SOC(:,1);
        
        resultLabel.Text = num2str(fval,'%.3f');
        try
            optCostField.Value   = sprintf('%.3f', fval);
            optCostField.Visible = 'on';
            optCostField.Enable  = 'on';
            drawnow limitrate;
        catch
        end
        display (num2str(fval))

        % Plot results
        R = struct();
        missing = {};
        vars = {'P_PV1','P_WT1','P_BESS1','P_EV1','P_EV_AC','EV_AC_SOC','NEV_AC', ...
                'P_conv','P_conv_pos','P_conv_neg','P_grid','P_diesel','P_MT2','P_CL1','P_NL1', ...
                'P_PV2','P_WT2','P_BESS2','P_EV2','P_EV_DC','EV_DC_SOC','NEV_DC','Elec_Price','Elec_SellPrice', ...
                'P_CL2','P_NL2','P_DR_NL1','P_DR_NL2','P_NL1_served','P_NL2_served', ...
                'SOC1','SOC2','EV1SOC','EV2SOC', ...
                'P_Shed_CL1','P_Shed_NL1','P_Shed_CL2','P_Shed_NL2', ...
                'P_Cur_PV1','P_Cur_PV2','P_Cur_WT1','P_Cur_WT2', ...
                'P_PV1_eff','P_PV2_eff','P_WT1_eff','P_WT2_eff','P_Load1_eff','P_Load2_eff','Wind_AC_status','Wind_DC_status','Eff_conv', ...
                'PV1_scen','PV1_prob','PV2_scen','PV2_prob','WT1_scen','WT1_prob','WT2_scen','WT2_prob', ...
                'Load1_scen','Load1_prob','Load2_scen','Load2_prob','PV1_Max','PV2_Max','WT1_Max','WT2_Max', ...
                'Elec_Price','Elec_SellPrice'};
        flds = vars;
        for ii = 1:numel(vars)
            if exist(vars{ii},'var')
                R.(flds{ii}) = eval(vars{ii});
            else
                missing{end+1} = vars{ii}; 
            end
        end
        if exist('colors','var')
            R.colors = colors;
        end
        setappdata(fig,'lastResults', R);

        try
            basePath = fileparts(mfilename('fullpath'));
            if isempty(basePath), basePath = pwd; end
            optFile = fullfile(basePath, 'Optimization_results_log.txt');
            fid = fopen(optFile, 'w');
            if fid ~= -1
                pv_unc_log = getappdata(fig,'pv_unc');
                wt_unc_log = getappdata(fig,'wt_unc');
                load_unc_log = getappdata(fig,'load_unc');
                fprintf(fid,'\n============================================================\n');
                fprintf(fid,'Optimization run: %s\n', datestr(now));
                fprintf(fid,'Objective cost: %.6f\n', fval);
                fprintf(fid,'\nUncertainty settings\n');
                fprintf(fid,'Load AC: mode=%s, level=%.4f, scen=%g, rho=%.4f, gamma=%.4f\n', char(string(getFieldOrDefaultRaw(load_unc_log.AC,'mode','Deterministic'))), getNumericScalar(getFieldOrDefaultRaw(load_unc_log.AC,'level',0),0), getNumericScalar(getFieldOrDefaultRaw(load_unc_log.AC,'num_scen',0),0), getNumericScalar(getFieldOrDefaultRaw(load_unc_log.AC,'rho',0),0), getNumericScalar(getFieldOrDefaultRaw(load_unc_log.AC,'gamma',0),0));
                fprintf(fid,'Load DC: mode=%s, level=%.4f, scen=%g, rho=%.4f, gamma=%.4f\n', char(string(getFieldOrDefaultRaw(load_unc_log.DC,'mode','Deterministic'))), getNumericScalar(getFieldOrDefaultRaw(load_unc_log.DC,'level',0),0), getNumericScalar(getFieldOrDefaultRaw(load_unc_log.DC,'num_scen',0),0), getNumericScalar(getFieldOrDefaultRaw(load_unc_log.DC,'rho',0),0), getNumericScalar(getFieldOrDefaultRaw(load_unc_log.DC,'gamma',0),0));
                fprintf(fid,'PV   AC: mode=%s, level=%.4f, scen=%g, rho=%.4f, gamma=%.4f\n', char(string(getFieldOrDefaultRaw(pv_unc_log.AC,'mode','Deterministic'))), getNumericScalar(getFieldOrDefaultRaw(pv_unc_log.AC,'level',0),0), getNumericScalar(getFieldOrDefaultRaw(pv_unc_log.AC,'num_scen',0),0), getNumericScalar(getFieldOrDefaultRaw(pv_unc_log.AC,'rho',0),0), getNumericScalar(getFieldOrDefaultRaw(pv_unc_log.AC,'gamma',0),0));
                fprintf(fid,'PV   DC: mode=%s, level=%.4f, scen=%g, rho=%.4f, gamma=%.4f\n', char(string(getFieldOrDefaultRaw(pv_unc_log.DC,'mode','Deterministic'))), getNumericScalar(getFieldOrDefaultRaw(pv_unc_log.DC,'level',0),0), getNumericScalar(getFieldOrDefaultRaw(pv_unc_log.DC,'num_scen',0),0), getNumericScalar(getFieldOrDefaultRaw(pv_unc_log.DC,'rho',0),0), getNumericScalar(getFieldOrDefaultRaw(pv_unc_log.DC,'gamma',0),0));
                fprintf(fid,'Wind AC: mode=%s, level=%.4f, scen=%g, rho=%.4f, gamma=%.4f\n', char(string(getFieldOrDefaultRaw(wt_unc_log.AC,'mode','Deterministic'))), getNumericScalar(getFieldOrDefaultRaw(wt_unc_log.AC,'level',0),0), getNumericScalar(getFieldOrDefaultRaw(wt_unc_log.AC,'num_scen',0),0), getNumericScalar(getFieldOrDefaultRaw(wt_unc_log.AC,'rho',0),0), getNumericScalar(getFieldOrDefaultRaw(wt_unc_log.AC,'gamma',0),0));
                fprintf(fid,'Wind DC: mode=%s, level=%.4f, scen=%g, rho=%.4f, gamma=%.4f\n', char(string(getFieldOrDefaultRaw(wt_unc_log.DC,'mode','Deterministic'))), getNumericScalar(getFieldOrDefaultRaw(wt_unc_log.DC,'level',0),0), getNumericScalar(getFieldOrDefaultRaw(wt_unc_log.DC,'num_scen',0),0), getNumericScalar(getFieldOrDefaultRaw(wt_unc_log.DC,'rho',0),0), getNumericScalar(getFieldOrDefaultRaw(wt_unc_log.DC,'gamma',0),0));
                fprintf(fid,'\nDR and EV settings\n');
                fprintf(fid,'DR AC: enabled=%d, shiftable_pct=%.2f\n', DR_AC_status, DR_AC_pct_eff);
                fprintf(fid,'DR DC: enabled=%d, shiftable_pct=%.2f\n', DR_DC_status, DR_DC_pct_eff);
                fprintf(fid,'EV count AC: %d\n', NEV_AC);
                fprintf(fid,'EV count DC: %d\n', NEV_DC);
                fprintf(fid,'\nKey optimization results\n');
                fprintf(fid,'Grid import energy (kWh): %.6f\n', dt*sum(max(P_grid,0)));
                fprintf(fid,'Grid export energy (kWh): %.6f\n', dt*sum(max(-P_grid,0)));
                fprintf(fid,'PV curtailment AC/DC (kWh): %.6f / %.6f\n', dt*sum(max(P_Cur_PV1,0)), dt*sum(max(P_Cur_PV2,0)));
                fprintf(fid,'Wind curtailment AC/DC (kWh): %.6f / %.6f\n', dt*sum(max(P_Cur_WT1,0)), dt*sum(max(P_Cur_WT2,0)));
                fprintf(fid,'Load shed AC CL/NL (kWh): %.6f / %.6f\n', dt*sum(max(P_Shed_CL1,0)), dt*sum(max(P_Shed_NL1,0)));
                fprintf(fid,'Load shed DC CL/NL (kWh): %.6f / %.6f\n', dt*sum(max(P_Shed_CL2,0)), dt*sum(max(P_Shed_NL2,0)));
                fprintf(fid,'BESS throughput AC/DC (kWh): %.6f / %.6f\n', dt*(sum(abs(P_BESS1chg))+sum(abs(P_BESS1dis))), dt*(sum(abs(P_BESS2chg))+sum(abs(P_BESS2dis))));
                fprintf(fid,'EV throughput AC/DC (kWh): %.6f / %.6f\n', dt*(sum(abs(P_EV_AC_chg(:)))+sum(abs(P_EV_AC_dis(:)))), dt*(sum(abs(P_EV_DC_chg(:)))+sum(abs(P_EV_DC_dis(:)))));
                fprintf(fid,'Peak served load AC/DC (kW): %.6f / %.6f\n', max(P_CL1 + P_NL1_served), max(P_CL2 + P_NL2_served));
                fclose(fid);
                disp(['Optimization log written to: ' optFile]);
            else
                disp('Could not open Optimization_results_log.txt for writing.');
            end
        catch ME_log
            disp(['Optimization logging error: ' ME_log.message]);
        end

        if ~isempty(missing)
            try
                uialert(fig, sprintf('Some plot data variables were not found:\n%s', strjoin(missing, ', ')), 'Plot data missing');
            catch
            end
        end
        % Render only the selected plot view
        renderBoth();
        plotStandaloneResultFigures(R, false);
        return;

cla(ax1);

colors = [
    [0.4660 0.6740 0.1880];   % PV - Green
    [0.3010 0.7450 0.9330];   % Wind - Teal
    [0      0.4470 0.7410];   % BESS - Blue
    [0.8500 0.3250 0.0980];   % EV - Orange
    [0.9290 0.6940 0.1250];   % ILC - Yellow
    [1      1      1];        % Grid - White
    [0.6    0.6    0.6];      % MT - Gray
];

% ---- AC power balance plot (must match Aeq1 exactly) ----
try
    P_EV1_total = sum(P_EV_AC, 2);
catch
    P_EV1_total = P_EV1;
end
P_PV1_plot = P_PV1 - P_Cur_PV1;
P_WT1_plot = (Wind_AC_status) * P_WT1 - P_Cur_WT1;
P_conv_AC = -P_conv;
P_Load1_adj = P_CL1 + P_NL1_served;

data = [P_PV1_plot, P_WT1_plot, P_BESS1, P_EV1_total, P_conv_AC, P_grid, P_diesel];
cla(ax1);
hold(ax1, 'on');
hBar = bar(ax1, data, 'stacked', 'FaceColor', 'flat');
for k = 1:length(hBar)
    hBar(k).CData = repmat(colors(k, :), size(hBar(k).YData, 1), 1);
end
hLoad1 = plot(ax1, P_Load1_adj,'k.','MarkerSize', 12);
lgd1 = legend(ax1, [hBar(:); hLoad1], {'PV','WT','BESS','EV','Conv','Grid','MT','Adj load'});
applyLegendStyle(lgd1);
lgd1.AutoUpdate = 'off';
lgd1.FontSize = 9;
title(ax1, 'Power balance: AC side');
ylabel(ax1, 'Power (kW)');

% ---- DC power balance plot ----
try
    P_EV2_total = sum(P_EV_DC, 2);
catch
    P_EV2_total = P_EV2;
end
P_PV2_plot = P_PV2 - P_Cur_PV2;
P_WT2_plot = (Wind_DC_status) * P_WT2 - P_Cur_WT2;
P_conv_DC = P_conv;
P_Load2_adj = P_CL2 + P_NL2_served;

data2 = [P_PV2_plot, P_WT2_plot, P_BESS2, P_EV2_total, P_conv_DC, P_MT2];
cla(ax2);
hold(ax2, 'on');
hBar2 = bar(ax2, data2, 'stacked', 'FaceColor', 'flat');
hBar2(1).CData = repmat(colors(1, :), size(hBar2(1).YData, 1), 1);
hBar2(2).CData = repmat(colors(2, :), size(hBar2(2).YData, 1), 1);
hBar2(3).CData = repmat(colors(3, :), size(hBar2(3).YData, 1), 1);
hBar2(4).CData = repmat(colors(4, :), size(hBar2(4).YData, 1), 1);
hBar2(5).CData = repmat(colors(5, :), size(hBar2(5).YData, 1), 1);
hBar2(6).CData = repmat(colors(7, :), size(hBar2(6).YData, 1), 1);
hLoad2 = plot(ax2, P_Load2_adj, 'k.','MarkerSize', 12);
lgd2 = legend(ax2, [hBar2(:); hLoad2], {'PV','WT','BESS','EV','Conv','MT','Adj load'});
applyLegendStyle(lgd2);
lgd2.AutoUpdate = 'off';
title(ax2, 'Power balance: DC side');
ylabel(ax2, 'Power (kW)');

cla(ax3);
        plot(ax3, SOC1);
        hold(ax3, 'on');
        plot(ax3, SOC2);
        hold(ax3, 'on');
        plot(ax3, EV1SOC);
        hold(ax3, 'on');
        plot(ax3, EV2SOC);
        lgd3 = legend(ax3, {'BESS_1','BESS_2','EV_1','EV_2'});

        applyLegendStyle(lgd3);
lgd3.AutoUpdate = 'off';

        lgd3.FontSize = 9;
        title(ax3, 'SOC: BESS','SOC: EVs');
        ylabel(ax3, 'SOC (%)');
        ylim(ax3,[0,130]);
        
        cla(ax4);
        plot(ax4, P_Shed_CL1);
        hold(ax4, 'on');
        plot(ax4, P_Shed_NL1);
        plot(ax4, P_Shed_CL2);
        plot(ax4, P_Shed_NL2);
        plot(ax4, P_Cur_PV1);
        plot(ax4, P_Cur_PV2);
        ylim(ax4,[0,20]);
        lgd4 = legend(ax4, {'C_1','N_1','C_2','N_2','P_1','P_2'});

        applyLegendStyle(lgd4);
        try
            switchPlot(plotSelector.Value);
        catch
        end

        lgd4.FontSize = 9;
        title(ax4, 'Renewables Curtailment');
        ylabel(ax4, 'Power (kW)');
        
    end

    % ===================== OpenDSS integration (Option A) =====================
    function loadDSSFeeder()
        % Load selected IEEE test feeder and populate bus list.
        try
            sys = dssSystemDD.Value;
        catch
            return;
        end

        thisDir   = fileparts(mfilename('fullpath'));
        feederRoot = fullfile(thisDir, 'OpenDSS_FeederLibrary');

        if strcmp(sys,'IEEE 13')
            masterPath = fullfile(feederRoot, 'IEEE13', 'Master.dss');
        elseif strcmp(sys,'IEEE 34')
            masterPath = fullfile(feederRoot, 'IEEE34', 'ieee34Mod1_noLC.dss');
        elseif strcmp(sys,'IEEE 123')
            masterPath = fullfile(feederRoot, 'IEEE123', 'Master_noLC.dss');
        else
            masterPath = fullfile(feederRoot, 'RealSys', 'Master.dss');
        end

        if ~exist(masterPath,'file')
            thisFile = mfilename('fullpath');
            thisDir  = fileparts(thisFile);
            if strcmp(sys,'IEEE 13')
                masterPath = fullfile(thisDir, 'OpenDSS_FeederLibrary', 'IEEE13', 'Master.dss');
            elseif strcmp(sys,'IEEE 34')
                masterPath = fullfile(thisDir, 'OpenDSS_FeederLibrary', 'IEEE34', 'Master.dss');
            elseif strcmp(sys,'IEEE 123')
                masterPath = fullfile(thisDir, 'OpenDSS_FeederLibrary', 'IEEE123', 'Master.dss');
            else
                masterPath = fullfile(thisDir, 'OpenDSS_FeederLibrary', 'RealSys', 'Master.dss');
            end
        end

        if ~exist(masterPath,'file')
            setQSTSStatus('Status: Master.dss not found (place OpenDSS_FeederLibrary next to this .m)');
            dssRunBtn.Enable = 'off';
            return;
        end

        try
            [DSSObj, DSSText, DSSCircuit] = startOpenDSS();
            feederDir = fileparts(masterPath);
        compileFeeder(DSSText, masterPath);
            buses = DSSCircuit.AllBusNames;
            if isempty(buses)
                error('No buses found in compiled feeder.');
            end

            % Sort for easier selection
            try
                buses = sort(string(buses)); buses = cellstr(buses);
            catch
            end
            dssBusDD.Items = buses;
            dssBusDD.Value = buses{1};
            setappdata(fig,'dssMasterPath', masterPath);
            setappdata(fig,'dssBusList', buses);

            dssRunBtn.Enable = 'on';
            setQSTSStatus(['Status: loaded ' sys]);
            updatePCCInfo();
        catch ME
            setQSTSStatus(['Status: QSTS error - ' ME.message]);
            dssRunBtn.Enable = 'off';
        end
    end

    function updatePCCInfo()
        % Update phase label automatically based on selected PCC bus.
        try
            masterPath = getappdata(fig,'dssMasterPath');
            if isempty(masterPath) || ~exist(masterPath,'file')                return;
            end
            bus = dssBusDD.Value;
            [phases, kvBaseLN, bus1] = getPCCBusInfo(masterPath, bus);           
            setappdata(fig,'dssPCCBus1', bus1);
            setappdata(fig,'dssPCCPhases', phases);
            setappdata(fig,'dssPCCkVBaseLN', kvBaseLN);
        catch        end
    end

    function runOpenDSSValidation()
        if ~isappdata(fig,'lastResults')
            uialert(fig,'Run optimization first so P_grid is available.','OpenDSS validation');
            return;
        end
        R = getappdata(fig,'lastResults');
        if isempty(R) || ~isfield(R,'P_grid')
            uialert(fig,'Optimization results do not include P_grid.','OpenDSS validation');
            return;
        end
        try
            R = runOpenDSSValidationCore(R, true);
            setappdata(fig,'lastResults', R);
            renderBoth();
            plotStandaloneQSTSFigure(R, getStandaloneColors());
        catch ME
            setQSTSStatus(['Status: QSTS error - ' ME.message]);
        end
    end

    function R = runOpenDSSValidationCore(R, updateUI)
        masterPath = getappdata(fig,'dssMasterPath');
        if isempty(masterPath) || ~exist(masterPath,'file')
            if updateUI
                setQSTSStatus('Status: feeder not loaded');
            end
            return;
        end

        pccBus = dssBusDD.Value;
        [phases, kvBaseLN, bus1] = getPCCBusInfo(masterPath, pccBus);

        Pgrid = R.P_grid(:); 
        if numel(Pgrid) ~= Num_var
            Pgrid = Pgrid(1:min(end,Num_var));
            if numel(Pgrid) < Num_var
                Pgrid(end+1:Num_var,1) = Pgrid(end);
            end
        end

        if updateUI
            setQSTSStatus(sprintf('Status: running QSTS (%s @ %s)', dssSystemDD.Value, pccBus));
            drawnow;
        end

        OD = validateOpenDSSOptionA(masterPath, pccBus, bus1, phases, kvBaseLN, Pgrid, zeros(size(Pgrid)));
        try
            OD.TestSystem = dssSystemDD.Value;
        catch
            OD.TestSystem = '';
        end

        % Attach to results struct for plotting
        R.OpenDSS = OD;
        try
            dssTimeField.Limits = [1 numel(Pgrid)];
            if dssTimeField.Value > numel(Pgrid), dssTimeField.Value = 1; end
        catch
        end

        % Update summary table (worst-case over horizon)
        if updateUI
            vmin = min(OD.Vmin_pu); vmax = max(OD.Vmax_pu);
            maxLine = max(OD.MaxLineLoading_pct);
            maxTrx  = max(OD.MaxTrxLoading_pct);
            lossKW  = mean(OD.Loss_kW);
            dssTable.Data = {
                'Vmin (pu)', sprintf('%.4f', vmin);
                'Vmax (pu)', sprintf('%.4f', vmax);
                'Max line loading (%)', sprintf('%.2f (Worst, %.1f A)', maxLine, OD.WorstLineAmps);
                'Max trx loading (%)',  sprintf('%.2f (Worst %.1f kVA)', maxTrx, OD.WorstTrxKVA);
                'Losses (kW)', sprintf('%.2f (avg)', lossKW)
                };
            setQSTSStatus('Status: done');

            % Append QSTS summary log in the same folder as this GUI file
            try
                basePath = fileparts(mfilename('fullpath'));
                if isempty(basePath), basePath = pwd; end
                qstsFile = fullfile(basePath, 'QSTS_results_log.txt');
                fid = fopen(qstsFile, 'w');
                if fid ~= -1
                    fprintf(fid,'\n============================================================\n');
                    fprintf(fid,'QSTS run: %s\n', datestr(now));
                    try, fprintf(fid,'Test system: %s\n', char(string(dssSystemDD.Value))); catch, end
                    try, fprintf(fid,'PCC bus: %s\n', char(string(pccBus))); catch, end
                    fprintf(fid,'Vmin (pu): %.6f\n', vmin);
                    fprintf(fid,'Vmax (pu): %.6f\n', vmax);
                    fprintf(fid,'Avg losses (kW): %.6f\n', lossKW);
                    fprintf(fid,'Max line loading (%%): %.6f\n', maxLine);
                    fprintf(fid,'Worst line amps: %.6f\n', OD.WorstLineAmps);
                    fprintf(fid,'Max transformer loading (%%): %.6f\n', maxTrx);
                    fprintf(fid,'Worst transformer kVA: %.6f\n', OD.WorstTrxKVA);
                    fprintf(fid,'Voltage spread max(Vmax-Vmin) (pu): %.6f\n', max(OD.Vmax_pu(:)-OD.Vmin_pu(:)));
                    fclose(fid);
                    disp(['QSTS log written to: ' qstsFile]);
                else
                    disp('Could not open QSTS_results_log.txt for writing.');
                end
            catch ME_log
                disp(['QSTS logging error: ' ME_log.message]);
            end
        end
    end

    function OD = validateOpenDSSOptionA(masterPath, pccBus, bus1, phases, kvBaseLN, Pgrid_kW, Qgrid_kvar)
        % OpenDSS validation (snapshot loop). MG is represented as:
        % - Load.MG_PCC for import
        % - Generator.MG_PCC for export

        [DSSObj, DSSText, DSSCircuit] = startOpenDSS(); %#ok<ASGLU>
        feederDir = fileparts(masterPath);
        compileFeeder(DSSText, masterPath);

        % Create MG elements once
        DSSText.Command = sprintf('New Load.MG_PCC bus1=%s phases=%d conn=wye kv=%.6f kW=0 kvar=0 model=1', ...
            bus1, phases, kvBaseLN);
        if phases == 3
            kvGen = kvBaseLN*sqrt(3);
        else
            kvGen = kvBaseLN;
        end
        DSSText.Command = sprintf('New Generator.MG_PCC bus1=%s phases=%d kv=%.6f kW=0 kvar=0 model=1', ...
            bus1, phases, kvGen);

        % Solve once to initialize circuit state and get node lists
        DSSText.Command = 'Set mode=snapshot';
        DSSText.Command = 'Solve';
        nodeNames = DSSCircuit.AllNodeNames;
        if isempty(nodeNames)
            nodeNames = DSSCircuit.AllBusNames; 
        end
        nNode = numel(nodeNames);
        Tn = numel(Pgrid_kW);
        NodeVpu = nan(nNode, Tn);

        % Build topology (if BusXY available)
        Topo = buildFeederTopology(masterPath, DSSCircuit);
        Vmin_pu = zeros(Tn,1);
        Vmax_pu = zeros(Tn,1);
        Loss_kW = zeros(Tn,1);
        MaxLineLoading_pct = zeros(Tn,1);
        MaxTrxLoading_pct  = zeros(Tn,1);

        worstLineName = '';
        worstTrxName  = '';
        worstLineVal = -inf;
        worstTrxVal  = -inf;
        worstLineAmps = NaN;
        worstTrxKVA  = NaN;

        for tIdx = 1:Tn
            P = Pgrid_kW(tIdx);
            Q = Qgrid_kvar(tIdx);

            if P >= 0
                DSSText.Command = sprintf('Edit Load.MG_PCC kW=%.6f kvar=%.6f', P, Q);
                DSSText.Command = 'Edit Generator.MG_PCC kW=0 kvar=0';
            else
                DSSText.Command = 'Edit Load.MG_PCC kW=0 kvar=0';
                DSSText.Command = sprintf('Edit Generator.MG_PCC kW=%.6f kvar=%.6f', -P, Q);
            end

            DSSText.Command = 'Set mode=snapshot';
            DSSText.Command = 'Solve';

            vpu = [];
            try
                vpu = DSSCircuit.AllNodeVmagPU;
            catch
            end
            if isempty(vpu)
                try
                    vpu = DSSCircuit.AllBusVmagPu;
                catch
                    vpu = [];
                end
            end
            try
                nn = min(numel(vpu), size(NodeVpu,1));
                NodeVpu(1:nn,tIdx) = vpu(1:nn);
            catch
            end
            if isempty(vpu)
                Vmin_pu(tIdx) = NaN;
                Vmax_pu(tIdx) = NaN;
            else
                Vmin_pu(tIdx) = min(vpu);
                Vmax_pu(tIdx) = max(vpu);
            end

            L = DSSCircuit.Losses; % W, var
            Loss_kW(tIdx) = L(1)/1000;

            % ---- Line loading (physical lines only; exclude switches and switch-like names) ----
            maxLinePctThis = 0;
            DSSLines = DSSCircuit.Lines;
            iLine = DSSLines.First;
            while iLine > 0
                try
                    lnName = DSSLines.Name;
                    isSwitch = false;
                    try
                        isSwitch = logical(DSSLines.IsSwitch);
                    catch
                    end
                    lnLower = lower(strtrim(char(lnName)));
                    nameLooksLikeSwitch = startsWith(lnLower,'sw') || contains(lnLower,'.sw');
                    if ~(isSwitch || nameLooksLikeSwitch)
                        DSSText.Command = ['Select Line.' lnName];
                        el = DSSCircuit.ActiveCktElement;
                        nph = 0;
                        try
                            nph = el.NumPhases;
                        catch
                        end
                        if isempty(nph) || nph <= 0
                            try
                                nph = DSSLines.Phases;
                            catch
                                nph = 0;
                            end
                        end
                        normA = 0;
                        emergA = 0;
                        try, normA = DSSLines.NormAmps; catch, end
                        try, emergA = DSSLines.EmergAmps; catch, end
                        ratingA = 0;
                        if ~isempty(emergA) && emergA > 0
                            ratingA = emergA; 
                        elseif ~isempty(normA) && normA > 0
                            ratingA = 1.5*normA;
                        end
                        cur = el.CurrentsMagAng; 
                        if ratingA > 0 && ~isempty(cur) && nph > 0
                            mags = cur(1:2:(2*nph)); 
                            mags = mags(isfinite(mags) & mags >= 0);
                            if ~isempty(mags)
                                avgI = mean(abs(mags));
                                pct = 100*avgI/ratingA;
                                if pct > maxLinePctThis
                                    maxLinePctThis = pct;
                                end
                                if pct > worstLineVal
                                    worstLineVal = pct;
                                    worstLineName = ['Line.' lnName];
                                    worstLineAmps = avgI;
                                end
                            end
                        end
                    end
                catch
                end
                iLine = DSSLines.Next;
            end
            MaxLineLoading_pct(tIdx) = maxLinePctThis;

            % ---- Transformer loading (kVA / rating) ----
            maxTrxPctThis = 0;
            DSSTrx = DSSCircuit.Transformers;
            iT = DSSTrx.First;
            while iT > 0
                try
                    txName = DSSTrx.Name;
                    rating = DSSTrx.kVA;
                    if rating > 0
                        DSSText.Command = ['Select Transformer.' txName];
                        el = DSSCircuit.ActiveCktElement;
                        ncond = el.NumConductors;
                        pows = el.Powers; 
                        kvpairs = pows(1:(2*ncond));
                        Psum = sum(kvpairs(1:2:end));
                        Qsum = sum(kvpairs(2:2:end));
                        S = sqrt(Psum^2 + Qsum^2);
                        pct = 100*S/rating;
                        if pct > maxTrxPctThis
                            maxTrxPctThis = pct;
                        end
                        if pct > worstTrxVal
                            worstTrxVal = pct;
                            worstTrxName = ['Transformer.' txName];
                            worstTrxKVA = S;
                        end
                    end
                catch
                end
                iT = DSSTrx.Next;
            end
            MaxTrxLoading_pct(tIdx) = maxTrxPctThis;
        end

        
        % Aggregate node voltages to bus-level voltages (max over phases/nodes)
        baseBus = cell(size(nodeNames));
        for ii=1:numel(nodeNames)
            nm = nodeNames{ii};
            tok = regexp(nm, '^[^\.]+', 'match', 'once');
            if isempty(tok), tok = nm; end
            baseBus{ii} = tok;
        end
        busNamesUnique = unique(baseBus, 'stable');
        nBus = numel(busNamesUnique);
        BusVpu = nan(nBus, Tn);
        for b=1:nBus
            idxs = strcmp(baseBus, busNamesUnique{b});
            if any(idxs)
                BusVpu(b,:) = max(NodeVpu(idxs,:), [], 1, 'omitnan');
            end
        end
OD = struct();
        OD.PCCBus = pccBus;
        OD.Bus1 = bus1;
        OD.Phases = phases;
        OD.kVBaseLN = kvBaseLN;
        OD.Vmin_pu = Vmin_pu;
        OD.Vmax_pu = Vmax_pu;
        OD.Loss_kW = Loss_kW;
        OD.MaxLineLoading_pct = MaxLineLoading_pct;
        OD.MaxTrxLoading_pct  = MaxTrxLoading_pct;
        OD.WorstLine = worstLineName;
        OD.WorstLineName = worstLineName;
        OD.WorstLineAmps = worstLineAmps;
        OD.WorstTrx  = worstTrxName;
        OD.WorstTrxKVA = worstTrxKVA;
        OD.NodeNames = nodeNames;
        OD.NodeVpu = NodeVpu;
        OD.BusNames = busNamesUnique;
        OD.BusVpu = BusVpu;
        OD.Topology = Topo;
    end

    function [phases, kvBaseLN, bus1] = getPCCBusInfo(masterPath, pccBus)
        % Compile feeder and extract bus nodes + kV base to build bus1 string.
        [~, DSSText, DSSCircuit] = startOpenDSS();
        feederDir = fileparts(masterPath);
        compileFeeder(DSSText, masterPath);

        DSSCircuit.SetActiveBus(pccBus);
        b = DSSCircuit.ActiveBus;

        nodes = b.Nodes;
        nodes = unique(nodes(:)');
        % Determine phases based on nodes 1-3
        ph = intersect(nodes, [1 2 3]);
        if numel(ph) >= 3
            phases = 3;
            bus1 = sprintf('%s.1.2.3', pccBus);
        elseif numel(ph) >= 1
            phases = 1;
            bus1 = sprintf('%s.%d', pccBus, ph(1));
        else
            phases = 3;
            bus1 = pccBus;
        end

        kvBaseLN = b.kVBase; % L-N base
        if kvBaseLN <= 0
            kvBaseLN = 2.4; % safe fallback (typical 4.16kV LL)
        end
    end

    function Topo = buildFeederTopology(masterPath, DSSCircuit)
        % Build a simple topology struct using BusXY (if available) and DSS line connectivity.
        Topo = struct('hasXY',false,'busNames',{{}},'X',[],'Y',[],'segX',[],'segY',[],'lineNames',{{}});
        try
            feederDir = fileparts(masterPath);
            candDirs = {feederDir, fullfile(feederDir,'network'), fileparts(feederDir)};
            d = [];
            ddir = '';
            for kk = 1:numel(candDirs)
                if exist(candDirs{kk},'dir')
                    dd = dir(fullfile(candDirs{kk},'*BusXY*.csv')); if isempty(dd), dd = dir(fullfile(candDirs{kk},'*busxy*.csv')); end
                    if isempty(dd), dd = dir(fullfile(candDirs{kk},'*Buscoords*.csv')); end
                    if isempty(dd), dd = dir(fullfile(candDirs{kk},'*Buscoords*.dss')); end
                    if isempty(dd), dd = dir(fullfile(candDirs{kk},'*BusXY*.CSV')); end
                    if ~isempty(dd)
                        d = dd; ddir = candDirs{kk};
                        break;
                    end
                end
            end
            if ~isempty(d)
                
fxy = fullfile(ddir, d(1).name);
[~,~,ext] = fileparts(fxy);

% --- Read bus coordinate table robustly ---
T = table();
try
    if strcmpi(ext,'.dss')
        % Some feeders (e.g., RealSys) store bus coordinates as CSV-like text in a .dss file.
        T = readtable(fxy, 'ReadVariableNames', false);
    else
        % Try with headers first
        T = readtable(fxy, 'ReadVariableNames', true);
        vars = lower(string(T.Properties.VariableNames));
        hasBus = any(vars=="bus" | vars=="busname" | vars=="name");
        hasX   = any(vars=="x");
        hasY   = any(vars=="y");
        if ~(hasBus && hasX && hasY)
            T = readtable(fxy, 'ReadVariableNames', false);
        end
    end
catch
    try
        T = readtable(fxy, 'ReadVariableNames', false);
    catch
        T = table();
    end
end

% Normalize variable names if headerless
if ~isempty(T) && width(T) >= 3
    if isempty(T.Properties.VariableNames) || any(contains(lower(string(T.Properties.VariableNames)),"var"))
        T = T(:,1:3);
        T.Properties.VariableNames = {'Bus','x','y'};
    else
        vars = lower(string(T.Properties.VariableNames));
        if ~(any(vars=="bus") && any(vars=="x") && any(vars=="y"))
            T = T(:,1:3);
            T.Properties.VariableNames = {'Bus','x','y'};
        end
    end
end

                % Expect columns: Bus, X, Y (case-insensitive)
                vars = lower(T.Properties.VariableNames);
                iBus = find(strcmp(vars,'bus') | strcmp(vars,'busname') | strcmp(vars,'name'), 1);
                iX   = find(strcmp(vars,'x'), 1);
                iY   = find(strcmp(vars,'y'), 1);
                if ~isempty(iBus) && ~isempty(iX) && ~isempty(iY)
                    busNames = string(T{:,iBus});
                    X = T{:,iX}; Y = T{:,iY};
                    Topo.hasXY = true;
                    Topo.busNames = cellstr(busNames);
                    Topo.X = X; Topo.Y = Y;
                    xyMap = containers.Map(lower(cellstr(busNames)), num2cell(1:numel(busNames)));
                else
                    xyMap = containers.Map();
                end
            else
                xyMap = containers.Map();
            end

            % Build line segments from DSS Lines
            segX = []; segY = []; lineNames = {};
            DSSLines = DSSCircuit.Lines;
            iLine = DSSLines.First;
            while iLine > 0
                lnName = DSSLines.Name;
                b1 = DSSLines.Bus1; b2 = DSSLines.Bus2;
                b1 = lower(regexprep(b1,'\..*$','')); % strip .1.2.3
                b2 = lower(regexprep(b2,'\..*$',''));
                if isKey(xyMap,b1) && isKey(xyMap,b2)
                    i1 = xyMap(b1); i2 = xyMap(b2);
                    segX(end+1,:) = [Topo.X(i1) Topo.X(i2)]; 
                    segY(end+1,:) = [Topo.Y(i1) Topo.Y(i2)]; 
                    lineNames{end+1,1} = ['Line.' lnName]; 
                end
                iLine = DSSLines.Next;
            end
            Topo.segX = segX;
            Topo.segY = segY;
            Topo.lineNames = lineNames;
        catch
        end
    end

    function [DSSObj, DSSText, DSSCircuit] = startOpenDSS()
        % Start OpenDSS COM engine safely.
        DSSObj = actxserver('OpenDSSEngine.DSS');
        if ~DSSObj.Start(0)
            error('Could not start OpenDSS engine. Ensure OpenDSS is installed and registered.');
        end
        try
            DSSObj.AllowForms = 0;
        catch
        end
        DSSText    = DSSObj.Text;
        DSSCircuit = DSSObj.ActiveCircuit;
        try
            DSSText.Command = 'Set DefaultBaseFrequency=60';
        catch
        end
    end

    function p = toDSSPath(p)
        p = strrep(p, '\\', '/');
    end

    function compileFeeder(DSSText, masterPath)
        % Compile feeder robustly (avoid compiling Master.dss that contains Clear).
        feederDir = fileparts(masterPath);
        [~, feederName] = fileparts(feederDir);
        feederName = lower(string(feederName));

        DSSText.Command = 'Clear';
        DSSText.Command = sprintf('Set Datapath="%s"', toDSSPath(feederDir));
        DSSText.Command = 'Set DefaultBaseFrequency=60';

        % Decide which files to redirect.
        if contains(feederName, "ieee13")
            lcFile  = fullfile(feederDir, 'IEEELineCodes.DSS');
            cktFile = fullfile(feederDir, 'IEEE13Nodeckt.dss');
            busxy   = fullfile(feederDir, 'IEEE13Node_BusXY.csv');
        elseif contains(feederName, "ieee34")
            lcFile  = '';  
            if contains(lower(string(masterPath)), "mod2")
                cktFile = fullfile(feederDir, 'ieee34Mod2_noLC.dss');
            else
                cktFile = fullfile(feederDir, 'ieee34Mod1_noLC.dss');
            end
            busxy = fullfile(feederDir, 'IEEE34_BusXY.csv');

        
        elseif contains(feederName, "ieee123")
            % IEEE 123-bus: Some OpenDSS COM DLL builds crash when creating LineCode objects.
            cktFile = fullfile(feederDir, 'Master_noLC.dss');
            if ~exist(cktFile,'file')
                cktFile = fullfile(feederDir, 'IEEE123Nodeckt_noLC.dss');
            end
            busxy = fullfile(feederDir, 'IEEE123_BusXY.csv');
            if ~exist(busxy,'file')
                busxy = fullfile(feederDir, 'BusCoords.dat');
            end
            lcFile = ''; %#ok<NASGU>

        elseif contains(feederName, "RealSys")
            % RealSys 240-bus test system (unbalanced distribution). Avoid executing its Master.dss (contains Clear).
            master = fullfile(feederDir, 'Master.dss');
            busxy = fullfile(feederDir, 'Buscoords.dss'); 
            lcFile = ''; 
            cktFile = ''; 

        else
            DSSText.Command = sprintf('Compile "%s"', toDSSPath(masterPath));
            return;
        end

        
if contains(feederName, "RealSys")
    if ~exist(master,'file')
        error('RealSys Master.dss not found.');
    end

    raw = fileread(master);
    L = splitlines(string(raw));
    missingFiles = {};  
    for k = 1:numel(L)
        s = strtrim(L(k));
        s = string(stripInlineDSSComment(char(s)));
        if s == "" || startsWith(s, "!") || startsWith(s, "//")
            continue;
        end
        sl = lower(s);
        if startsWith(sl, "clear")
            continue;
        elseif startsWith(sl, "new circuit.")
            DSSText.Command = char(s);
        elseif startsWith(sl, "redirect")
            tok = regexp(char(s), '^redirect\s+("?)([^"]+)\1', 'tokens', 'once', 'ignorecase');
            if ~isempty(tok)
                fRel = strtrim(tok{2});
                fRel = strrep(fRel, '''', '');
                fAbs = fRel;
                if ~exist(fAbs,'file')
                    fAbs = fullfile(feederDir, fRel);
                end
                if exist(fAbs,'file')
                    DSSText.Command = sprintf('Redirect "%s"', toDSSPath(fAbs));
                else
                    missingFiles{end+1} = sprintf('Missing file: %s', fAbs); %#ok<AGROW>
                end
            end
        else
            % RealSys Master includes plotting/report commands (Show/Plot/Export/Save) that can
            if startsWith(sl, "show") || startsWith(sl, "plot") || startsWith(sl, "export") || startsWith(sl, "save")
                continue;
            end
            DSSText.Command = char(s);
        end
    end

    if ~isempty(missingFiles)
        error(strjoin(missingFiles, newline));
    end

    if exist(busxy,'file')
        DSSText.Command = sprintf('Buscoords "%s"', toDSSPath(busxy));
    end
else
    if exist(lcFile,'file'),  DSSText.Command = sprintf('Redirect "%s"', toDSSPath(lcFile));  end
    if exist(cktFile,'file'), DSSText.Command = sprintf('Redirect "%s"', toDSSPath(cktFile)); end

    % Load bus coordinates for topology plot
    if exist(busxy,'file')
        if endsWith(lower(busxy), '.csv')
            DSSText.Command = sprintf('Buscoords "%s"', toDSSPath(busxy));
        else
            DSSText.Command = sprintf('Redirect "%s"', toDSSPath(busxy));
        end
    end
end

        try
            DSSText.Command = 'Solve';
        catch
        end
    end

function showNoScenario(ax, whatStr)
    cla(ax);
    try
        msg = sprintf('No scenario data for %s.\nSet Uncertainty Mode = Scenario and re-run Optimization.', whatStr);
        text(ax,0.05,0.55, msg, 'FontSize',11, 'HorizontalAlignment','left');
        axis(ax,'off');
    catch
    end
end

function plotScenarioSpaghetti(ax, baseSeries, scenMat, prob, titleStr, withLegend)

    cla(ax); hold(ax,'on');

    baseSeries = baseSeries(:);
    if isempty(scenMat) || ~isnumeric(scenMat)
        showNoScenario(ax, titleStr);
        return;
    end
    N = size(scenMat,1);
    tIdx = (1:N)';

    % Limit number of spaghetti lines for readability
    S = size(scenMat,2);
    maxShow = min(30, S);
    try
        showIdx = unique(round(linspace(1,S,maxShow)));
    catch
        showIdx = 1:maxShow;
    end

    % Spaghetti (light)
    for k = 1:numel(showIdx)
        plot(ax, tIdx, scenMat(:,showIdx(k)), 'LineWidth', 0.5);
    end

    % Quantiles across scenarios at each time
    try
        q = prctile(scenMat', [10 50 90])';  
        p10 = q(:,1); p50 = q(:,2); p90 = q(:,3);
    catch
        % fallback if prctile unavailable
        p10 = min(scenMat,[],2);
        p50 = mean(scenMat,2);
        p90 = max(scenMat,[],2);
    end

    expv = mean(scenMat,2);
    if ~isempty(prob)
        try
            p = prob(:);
            p = p / sum(p);
            if numel(p) == S
                expv = scenMat * p;
            end
        catch
        end
    end

    hBase = plot(ax, tIdx, baseSeries, 'k-', 'LineWidth', 2.0);
    hExp  = plot(ax, tIdx, expv, '--', 'LineWidth', 2.0);
    hMed  = plot(ax, tIdx, p50, '-', 'LineWidth', 2.2);
    hP10  = plot(ax, tIdx, p10, ':', 'LineWidth', 1.6);
    hP90  = plot(ax, tIdx, p90, ':', 'LineWidth', 1.6);
    ylabel(ax,'Power (kW)');
    xlabel(ax,'Time step');

    if withLegend
        lgd = legend(ax, [hBase hExp hMed hP10 hP90], {'Base/Used','Expected','Median','P10','P90'}, 'Location','eastoutside');
        applyLegendStyle(lgd);
    end
    grid(ax,'on');
end

    function applyLegendStyle(lgd)
        if isempty(lgd) || ~isvalid(lgd)
            return;
        end
        if isprop(lgd,'Box'),         lgd.Box = 'off'; end
        if isprop(lgd,'AutoUpdate'),  lgd.AutoUpdate = 'off'; end
        if isprop(lgd,'Location'),    lgd.Location = 'eastoutside'; end
        if isprop(lgd,'Orientation'), lgd.Orientation = 'vertical'; end
        if isprop(lgd,'NumColumns'),  lgd.NumColumns = 1; end
        if isprop(lgd,'FontSize'),    lgd.FontSize = 8; end
        if isprop(lgd,'ItemTokenSize'), lgd.ItemTokenSize = [10 8]; end
        if isprop(lgd,'Interpreter'), lgd.Interpreter = 'none'; end
    end

    function toggleEnableFromCheckbox(cb, btn)
        if cb.Value
            btn.Enable = 'on';
        else
            btn.Enable = 'off';
        end
    end

    function onCompToggle(cb, cfgBtn, lineHandle)
        % Unified UI callback:
        try
            if ~isempty(cfgBtn) && isgraphics(cfgBtn)
                toggleEnableFromCheckbox(cb, cfgBtn);
            end
        catch
        end
        try
            if ~isempty(lineHandle) && isgraphics(lineHandle)
                updateConnection(lineHandle, cb.Value);
            end
        catch
        end
    end

    function updateConnection(hLine, isOn)
        % Set connection line style based on component state
        if isOn
            set(hLine, 'LineStyle', '-', 'Color','k', 'LineWidth', 2.2);
        else
            set(hLine, 'LineStyle', ':', 'Color',[0.6 0.6 0.6], 'LineWidth', 1.2);
        end
    end

    function hLine = drawDevice(ax, xCenter, yBox, labelStr, yBus)
        boxW = 0.06; boxH = 0.06;
        x0 = xCenter - boxW/2;
        y0 = yBox - boxH/2;
        rectangle(ax, 'Position', [x0 y0 boxW boxH], 'FaceColor', 'w', 'EdgeColor', 'k');

        labelOffset = 0.018; % reduced to avoid overlaps
        if yBox >= yBus
            text(ax, xCenter, y0 + boxH + labelOffset, labelStr, 'FontSize',13, ...
                'HorizontalAlignment','center', 'VerticalAlignment','bottom');
        else
            text(ax, xCenter, y0 - labelOffset, labelStr, 'FontSize',13, ...
                'HorizontalAlignment','center', 'VerticalAlignment','top');
        end

        if yBox >= yBus
            hLine = plot(ax, [xCenter xCenter], [yBus y0], ':', 'Color',[0.6 0.6 0.6], 'LineWidth', 1.2);
        else
            hLine = plot(ax, [xCenter xCenter], [yBus y0+boxH], ':', 'Color',[0.6 0.6 0.6], 'LineWidth', 1.2);
        end
    end

end % end ModularEMSGUI

function out = stripInlineDSSComment(in)
out = in;
if isempty(in), return; end
inChar = char(in);
inQuotes = false;
cutPos = 0;
i = 1;
while i <= length(inChar)
    c = inChar(i);
    if c == '"'
        inQuotes = ~inQuotes;
        i = i + 1;
        continue;
    end
    if ~inQuotes
        if c == '!'
            cutPos = i;
            break;
        end
        if c == '/' && i < length(inChar) && inChar(i+1) == '/'
            cutPos = i;
            break;
        end
    end
    i = i + 1;
end
if cutPos > 0
    out = strtrim(inChar(1:cutPos-1));
else
    out = strtrim(inChar);
end
end

function s = ternEnable(tf)
    if tf
        s = 'on';
    else
        s = 'off';
    end
end

% ===== Helpers for EV Configure dialog (AC side) =====
function localEVSyncRows(spN, tbl, defaultFn)
    n = max(1, round(spN.Value));
    D = tbl.Data;
    if isempty(D)
        D = defaultFn(n);
    end
    if size(D,1) < n
        D = [D; defaultFn(n - size(D,1))];
    elseif size(D,1) > n
        D = D(1:n,:);
    end
    tbl.Data = D;
end

function localEVSave(spN, tbl, d, NEVField, EVTable, ...
                     EV1MaxField, EffEV1Field, EV1CapField, ...
                     EV1SOCInitField, EV1SOCMinField, EV1SOCMaxField, ...
                     EV1SOCTarField, EV1ARRField, EV1DEPField, defaultFn)
    n = max(1, round(spN.Value));
    D = tbl.Data;
    if isempty(D)
        D = defaultFn(n);
    end
    if size(D,1) ~= n
        localEVSyncRows(spN, tbl, defaultFn);
        D = tbl.Data;
    end

    try
        if ~isempty(NEVField) && isgraphics(NEVField)
            NEVField.Value = n;
        end
    catch
    end
    try
        if ~isempty(EVTable) && isgraphics(EVTable)
            EVTable.Data = D;
        end
    catch
    end

    try
        if ~isempty(EV1MaxField) && isgraphics(EV1MaxField),     EV1MaxField.Value     = D(1,1); end
        if ~isempty(EffEV1Field) && isgraphics(EffEV1Field),     EffEV1Field.Value     = D(1,2); end
        if ~isempty(EV1CapField) && isgraphics(EV1CapField),     EV1CapField.Value     = D(1,3); end
        if ~isempty(EV1SOCInitField) && isgraphics(EV1SOCInitField), EV1SOCInitField.Value = D(1,4); end
        if ~isempty(EV1SOCMinField) && isgraphics(EV1SOCMinField),   EV1SOCMinField.Value  = D(1,5); end
        if ~isempty(EV1SOCMaxField) && isgraphics(EV1SOCMaxField),   EV1SOCMaxField.Value  = D(1,6); end
        if ~isempty(EV1SOCTarField) && isgraphics(EV1SOCTarField),   EV1SOCTarField.Value  = D(1,7); end
        if ~isempty(EV1ARRField) && isgraphics(EV1ARRField),     EV1ARRField.Value     = D(1,8); end
        if ~isempty(EV1DEPField) && isgraphics(EV1DEPField),     EV1DEPField.Value     = D(1,9); end
    catch
    end

    try
        uiresume(d);
    catch
    end
    try
        if isvalid(d), delete(d); end
    catch
    end
end

function localCloseDialog(d)
    try
        uiresume(d);
    catch
    end
    try
        if isvalid(d), delete(d); end
    catch
    end
end

function v = localGetCallerVar(varName, fallback)
    try
        ex = evalin('caller', sprintf('exist(''%s'',''var'')', varName));
        if ex
            v = evalin('caller', varName);
        else
            v = fallback;
        end
    catch
        v = fallback;
    end

    if isempty(v)
        v = fallback;
    end
    if iscell(v)
        v = v{1};
    end
    if isnumeric(v) && ~isscalar(v)
        v = v(1);
    end
end

% Local helpers (cost vectors)
function s = stringOrDash(v)
    try
        if isempty(v)
            s = '-';
        else
            s = char(string(v));
        end
    catch
        s = '-';
    end
end
