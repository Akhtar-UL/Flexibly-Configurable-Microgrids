function net = OpenDSS_QSTS(P_pcc_kW, Q_pcc_kvar, dt_hr)
% Run OpenDSS QSTS using PCC power profiles.


    net = [];

    if nargin < 3 || isempty(dt_hr)
        dt_hr = 1;
    end
    P_pcc_kW = P_pcc_kW(:);
    Q_pcc_kvar = Q_pcc_kvar(:);
    if numel(Q_pcc_kvar) ~= numel(P_pcc_kW)
        Q_pcc_kvar = zeros(size(P_pcc_kW));
    end

    % ---- Feeder selection (populate IEEE test feeders from OpenDSS if found) ----
    feeders = local_find_feeders();
    if isempty(feeders)
        error('No OpenDSS feeders found. Install OpenDSS or add feeder .dss files to OpenDSS_FeederLibrary.');
    end

    [idx, ok] = listdlg('ListString', {feeders.name}, ...
                        'SelectionMode', 'single', ...
                        'PromptString', 'Select an OpenDSS test feeder (master .dss):', ...
                        'Name', 'OpenDSS QSTS');
    if ~ok || isempty(idx)
        return; 
    end
    feeder = feeders(idx);

    % ---- Start OpenDSS ----
    try
        dssObj = actxserver('OpenDSSEngine.DSS');
    catch
        error(['OpenDSS COM server not available. ' ...
               'Install OpenDSS and ensure it is registered (Windows).']);
    end
    if ~dssObj.Start(0)
        error('Failed to start OpenDSS engine.');
    end

    dssText    = dssObj.Text;
    dssCircuit = dssObj.ActiveCircuit;
    dssSol     = dssCircuit.Solution;

    % Compile the feeder.
    dssText.Command = sprintf('Clear');
    dssText.Command = sprintf('Compile "%s"', feeder.master);

    % ---- PCC bus selection ----
    busNames = dssCircuit.AllBusNames;
    if isempty(busNames)
        error('No buses detected after compiling feeder.');
    end
    [bidx, bok] = listdlg('ListString', busNames, ...
                          'SelectionMode', 'single', ...
                          'PromptString', 'Select the PCC bus where the microgrid connects:', ...
                          'Name', 'OpenDSS QSTS');
    if ~bok || isempty(bidx)
        return; % user cancelled
    end
    pcc_bus_full = busNames{bidx};

    mode = questdlg('Reactive power setting for MG at PCC?', 'OpenDSS QSTS', ...
                    'Use Q(t) from EMS', 'Fixed PF', 'Fixed Q', 'Use Q(t) from EMS');
    if isempty(mode)
        mode = 'Use Q(t) from EMS';
    end
    fixed_pf = 1.0;
    fixed_q  = 0.0;
    switch mode
        case 'Fixed PF'
            answ = inputdlg({'Enter power factor (0..1). Lagging (+Q) assumed:'}, ...
                            'Fixed PF', [1 60], {'0.98'});
            if isempty(answ), return; end
            fixed_pf = max(0.0, min(1.0, str2double(answ{1})));
            if isnan(fixed_pf) || fixed_pf <= 0
                fixed_pf = 0.98;
            end
        case 'Fixed Q'
            answ = inputdlg({'Enter constant Q at PCC (kvar). Positive = injection:'}, ...
                            'Fixed Q', [1 60], {'0'});
            if isempty(answ), return; end
            fixed_q = str2double(answ{1});
            if isnan(fixed_q), fixed_q = 0; end
    end

    % ---- Create / replace an aggregated MG injection at PCC ----
[pcc_bus_full_full, pcc_phases, kvLN] = local_build_bus1(dssCircuit, pcc_bus_full);
if isempty(kvLN) || kvLN <= 0
    kvLN = 7.2; 
end
% For a 3-phase Generator element, OpenDSS expects kV as L-L. For 1-phase, use L-N.
if pcc_phases >= 2
    kv_for_gen = kvLN * sqrt(3);
else
    kv_for_gen = kvLN;
end

local_ensure_mg_pcc(dssText, dssCircuit, pcc_bus_full_full, pcc_phases, kv_for_gen);
% ---- QSTS loop (snapshot per timestep) ----
    N = numel(P_pcc_kW);
    time_hr = (0:N-1)' * dt_hr;

    Vmin_pu = nan(N,1);
    Vmax_pu = nan(N,1);
    Vpcc_pu = nan(N,1);
    losses_kW = nan(N,1);
    max_overload_pu = nan(N,1);
    Q_used = zeros(N,1);

    for k = 1:N
        Pk = P_pcc_kW(k);
        Qk = Q_pcc_kvar(k);

        switch mode
            case 'Use Q(t) from EMS'
                % keep Qk
            case 'Fixed Q'
                Qk = fixed_q;
            case 'Fixed PF'
                % Approximate kvar from kW and PF (lagging assumed)
                pf = fixed_pf;
                if abs(Pk) < 1e-6 || pf >= 1
                    Qk = 0;
                else
                    S = abs(Pk) / pf; % kVA
                    Qmag = sqrt(max(0, S^2 - Pk^2));
                    Qk = sign(Pk) * Qmag; % keep consistent direction
                end
        end
        Q_used(k) = Qk;

        % Update MG element
        dssText.Command = sprintf('Edit Generator.MG_PCC kW=%.6g kvar=%.6g', Pk, Qk);

        % Solve snapshot
        dssSol.Mode = 0; % snapshot
        dssSol.Solve;

        % Voltages (pu)
        Vpu = dssCircuit.AllBusVmagPu;
        if ~isempty(Vpu)
            Vmin_pu(k) = min(Vpu);
            Vmax_pu(k) = max(Vpu);
        end

        % PCC voltage (average of available phase magnitudes at the selected bus)
try
    [Vpcc_pu(k)] = local_get_bus_vpu(dssCircuit, pcc_bus);
catch
    % leave as NaN if lookup fails
end

        % Losses (W -> kW)
        try
            L = dssCircuit.Losses; % [P_loss(W) Q_loss(var)]
            losses_kW(k) = L(1) / 1000;
% Max line loading (% on emergency basis) across all physical lines (avg-phase)
try
    max_overload_pu(k) = local_max_line_loading_pu(dssCircuit);
catch
    % leave NaN
end

        catch
        end

        % Max loading based on line emergency rating (or 1.5x NormAmps fallback)
    end

    net = struct();
    net.time_hr = time_hr;
    net.P_pcc_kW = P_pcc_kW;
    net.Q_pcc_kvar = Q_used;
    net.Vmin_pu = Vmin_pu;
    net.Vmax_pu = Vmax_pu;
    net.Vpcc_pu = Vpcc_pu;
    net.losses_kW = losses_kW;
    net.max_overload_pu = max_overload_pu;
    net.feeder_name = feeder.name;
    net.feeder_master = feeder.master;
    net.pcc_bus_full = pcc_bus_full;

% ---- Plots: network behavior over the QSTS horizon ----
try
    f = figure('Name','OpenDSS QSTS Results','NumberTitle','off');
    t_hr = time_hr(:);

    % 1) Voltage envelope
    subplot(3,1,1);
    plot(t_hr, Vmin_pu, 'LineWidth', 1.2); hold on;
    plot(t_hr, Vmax_pu, 'LineWidth', 1.2);
    plot(t_hr, Vpcc_pu, 'LineWidth', 1.2);
    yline(0.95, '--'); yline(1.05, '--');
    grid on;
    title('Feeder voltage envelope (pu)');
    xlabel('Time (h)'); ylabel('Voltage (pu)');
    legend('V_{min}','V_{max}','V_{PCC}','0.95','1.05','Location','best');

    % 2) Max loading
    subplot(3,1,2);
    plot(t_hr, 100*max_overload_pu, 'LineWidth', 1.2); hold on;
    yline(100, '--');
    grid on;
    title('Max line loading (Avg-phase, Emerg basis %)');
    xlabel('Time (h)'); ylabel('Loading (%)');
    legend('Max loading','100%','Location','best');

    % 3) PCC exchange and losses
    subplot(3,1,3);
    yyaxis left;
    plot(t_hr, P_pcc_kW, 'LineWidth', 1.2);
    ylabel('P_{PCC} (kW)');
    yyaxis right;
    plot(t_hr, losses_kW, 'LineWidth', 1.2);
    ylabel('Losses (kW)');
    grid on;
    title('PCC exchange and feeder losses');
    xlabel('Time (h)');
    legend('P_{PCC}','Losses','Location','best');

    drawnow;
catch
    % Do not fail if plotting is not available (headless / UI limitations)
end

% Export to base workspace for inspection
try
    assignin('base','QSTS_net', net);
catch
end

end

% ---------------------------- helpers ----------------------------

function feeders = local_find_feeders()
        feeders = struct('name', {}, 'master', {});
    here = fileparts(mfilename('fullpath'));

    defaultLib = fullfile(here, 'OpenDSS_FeederLibrary');

    msg = ['Select the OpenDSS feeder library folder.' newline newline ...
       'Recommended: keep a local folder containing IEEE test feeders.' newline ...
       'Each feeder should be in its own subfolder with a Master.dss (or *master*.dss).'];
useWhich = questdlg(msg, 'Feeder Library', 'Use bundled library', 'Choose folder...', 'Use bundled library');
libRoot = defaultLib;
    if strcmpi(useWhich, 'Choose folder...')
        chosen = uigetdir(defaultLib, 'Select OpenDSS feeder library folder');
        if ~isequal(chosen, 0)
            libRoot = char(chosen);
        end
    end

    feeders = local_find_master_dss(libRoot);

    % If user chose an empty folder, fall back to bundled library.
    if isempty(feeders) && ~strcmpi(libRoot, defaultLib)
        feeders = local_find_master_dss(defaultLib);
    end

    % De-duplicate by master path
    if ~isempty(feeders)
        masters = {feeders.master};
        [~, ia] = unique(lower(masters), 'stable');
        feeders = feeders(ia);
    end
end

function list = local_find_master_dss(rootDir)
    list = struct('name', {}, 'master', {});
    if isempty(rootDir) || ~exist(rootDir, 'dir')
        return;
    end

    % Prioritize common IEEE masters if present
    preferred = {'IEEE13', 'IEEE 13', '13Bus', 'IEEE34', '34Bus', 'IEEE123', '123Bus'};
    d = dir(fullfile(rootDir, '**', '*.dss'));
    for k = 1:numel(d)
        p = fullfile(d(k).folder, d(k).name);
        nm = d(k).name;

        isMaster = contains(lower(nm), 'master') || contains(lower(nm), 'ckt') || strcmpi(nm, 'Master.dss');
        if ~isMaster
            continue;
        end

        % Create a human-friendly name
        rel = strrep(p, rootDir, '');
        rel = strrep(rel, filesep, '/');
        dispName = strtrim(rel);
        if startsWith(dispName, '/'), dispName = dispName(2:end); end

        score = 0;
        for j = 1:numel(preferred)
            if contains(lower(dispName), lower(preferred{j}))
                score = score + 1;
            end
        end

        list(end+1).name = sprintf('%s', dispName); 
        list(end).master = p;
        list(end).score = score; 
    end

    if isempty(list)
        return;
    end

    % Sort by score desc, then name
    scores = [list.score];
    [~, order] = sortrows([(-scores(:)) (1:numel(list))']);
    list = list(order);

    % Remove score field
    if isfield(list, 'score')
        list = rmfield(list, 'score');
    end

end

function local_ensure_mg_pcc(dssText, dssCircuit, bus1_full, phases, kv_for_gen)
% Ensure Generator.MG_PCC exists; if not, create it. Otherwise, update bus/kV.
    if isempty(phases) || phases < 1
        phases = 3;
    end
    if isempty(kv_for_gen) || kv_for_gen <= 0
        kv_for_gen = 4.16;
    end

    existsMG = false;
    try
        g = dssCircuit.Generators;
        if g.First > 0
            while true
                if strcmpi(g.Name, 'MG_PCC')
                    existsMG = true;
                    break
                end
                if g.Next <= 0
                    break
                end
            end
        end
    catch
        existsMG = false;
    end

    if ~existsMG
        dssText.Command = sprintf('New Generator.MG_PCC phases=%d bus1=%s kV=%.6g kW=0 kvar=0 model=1', phases, bus1_full, kv_for_gen);
    else
        dssText.Command = sprintf('Edit Generator.MG_PCC enabled=yes phases=%d bus1=%s kV=%.6g', phases, bus1_full, kv_for_gen);
        dssText.Command = 'Edit Generator.MG_PCC kW=0 kvar=0';
    end
end

function [bus1_full, phases, kvLN] = local_build_bus1(dssCircuit, busName)
    bus1_full = busName;
    phases = 3;
    kvLN = [];
    try
        dssCircuit.SetActiveBus(busName);
        b = dssCircuit.ActiveBus;
        kvLN = b.kVBase; % L-N base
        nodes = b.Nodes; % node numbers present at this bus
        if ~isempty(nodes)
            nodes = unique(nodes(:)');
            phases = min(3, numel(nodes));
            nodeStr = sprintf('.%d', nodes);
            bus1_full = [busName nodeStr];
        else
            phases = 3;
        end
    catch
        % keep defaults
        bus1_full = busName;
        phases = 3;
        kvLN = [];
    end
end

function Vpcc = local_get_bus_vpu(dssCircuit, busName)
% Robustly get average pu voltage magnitude at a bus (across available nodes).
    Vpcc = NaN;
    dssCircuit.SetActiveBus(busName);
    v = dssCircuit.ActiveBus.puVmagAngle; % [V1 ang1 V2 ang2 ...]
    if isempty(v)
        return;
    end
    mags = v(1:2:end);
    if isempty(mags)
        return;
    end
    Vpcc = mean(mags);
end

function max_pu = local_max_line_loading_pu(dssCircuit)
% Compute max line loading using physical line sections only.
    max_pu = NaN;
    L = dssCircuit.Lines;
    if L.First <= 0
        return;
    end
    maxval = -inf;
    while true
        try
            lnName = '';
            try, lnName = char(L.Name); catch, end
            isSwitch = false;
            try
                isSwitch = logical(L.IsSwitch);
            catch
            end
            nameLooksLikeSwitch = false;
            if ~isempty(lnName)
                lnn = lower(strtrim(lnName));
                nameLooksLikeSwitch = startsWith(lnn,'sw') || contains(lnn,'.sw');
            end

            if ~(isSwitch || nameLooksLikeSwitch)
                normA = 0;
                emergA = 0;
                try, normA = L.NormAmps; catch, end
                try, emergA = L.EmergAmps; catch, end
                ratingA = 0;
                if ~isempty(emergA) && emergA > 0
                    ratingA = emergA;
                elseif ~isempty(normA) && normA > 0
                    ratingA = 1.5 * normA;
                end
                if ratingA > 0
                    dssCircuit.SetActiveElement(['Line.' lnName]);
                    el = dssCircuit.ActiveCktElement;
                    nph = 0;
                    try
                        nph = el.NumPhases;
                    catch
                    end
                    if isempty(nph) || nph <= 0
                        try
                            nph = L.Phases;
                        catch
                            nph = 0;
                        end
                    end
                    cur = el.CurrentsMagAng; % [I1 ang1 I2 ang2 ...] for all conductors and terminals
                    if ~isempty(cur) && nph > 0
                        mags = cur(1:2:(2*nph)); % terminal-1 phase conductors only
                        mags = mags(isfinite(mags) & mags >= 0);
                        if ~isempty(mags)
                            pu = mean(abs(mags)) / ratingA;
                            if pu > maxval
                                maxval = pu;
                            end
                        end
                    end
                end
            end
        catch
        end
        if L.Next <= 0
            break;
        end
    end
    if isfinite(maxval)
        max_pu = maxval;
    end
end
