function [lb, ub, A, b, SOCmat, names, EVPmat, slackCount] = EV_FleetExtra_Module(sideTag, t, Num_var, evList, totalCols, startCol0, Grid_status, ILC_status, EV_status)
% Extra EV fleet constraints for appended EV variables.

if nargin < 7, Grid_status = 1; end
if nargin < 8, ILC_status  = 1; end
if nargin < 9, EV_status   = 1; end

N = numel(evList);
slackCount = 0;

if N < 1
    lb = zeros(0,1);
    ub = zeros(0,1);
    A = zeros(0,totalCols);
    b = zeros(0,1);
    SOCmat = zeros(Num_var,0);
    names = {};
    EVPmat = zeros(Num_var,0);
    return;
end

getf = @(s, keys, def) local_getFieldNumeric(s, keys, def);

if EV_status == 0
    lb = zeros(2*N*Num_var,1);
    ub = zeros(2*N*Num_var,1);
    A  = zeros(0,totalCols);
    b  = zeros(0,1);
    SOCmat = zeros(Num_var,N);
    EVPmat = zeros(Num_var,N);
    names = local_makeNames(sideTag,N);
    return;
end

lockToInit = false;
if strcmpi(sideTag,'AC')
    lockToInit = (Grid_status == 0);
else
    lockToInit = (Grid_status == 0) || (ILC_status == 0);
end

lb = zeros(2*N*Num_var, 1);
ub = zeros(2*N*Num_var, 1);
EVPmat = zeros(Num_var,N);
names = local_makeNames(sideTag,N);

for i = 1:N
    pmax = abs(getf(evList(i), {'PMax','Pmax','P_EV_max','P_EV1_max','P_EV2_max','PowerMax'}, 0));
    Ta = getf(evList(i), {'Arrival','Ta','Ta1','Ta2'}, 0);
    Td = getf(evList(i), {'Departure','Td','Td1','Td2'}, Num_var*t);

    Ta_idx = local_timeToIdx(Ta, t, Num_var);
    Td_idx = local_timeToIdx(Td, t, Num_var);
    if Td_idx < Ta_idx
        tmp = Ta_idx;
        Ta_idx = Td_idx;
        Td_idx = tmp;
    end

    EVP = ones(Num_var,1);
    EVP(1:Ta_idx-1) = 0;
    EVP(Td_idx+1:end) = 0;
    EVPmat(:,i) = EVP;

    base = (i-1)*2*Num_var;
    lb(base+1:base+Num_var) = 0;            % discharge
    ub(base+1:base+Num_var) = pmax * EVP;   % discharge
    lb(base+Num_var+1:base+2*Num_var) = -pmax * EVP; % charge
    ub(base+Num_var+1:base+2*Num_var) = 0;           % charge
end

A = [];
b = [];
Ttri = tril(ones(Num_var));

for i = 1:N
    cap    = max(1e-6, getf(evList(i), {'Capacity','Cap','EV_CAP','EV_CAP1','EV_CAP2'}, 1));
    eff    = max(1e-6, getf(evList(i), {'Eff','Efficiency','Eff_EV','Eff_EV1','Eff_EV2'}, 1));
    soc0   = getf(evList(i), {'SOCInit','SOC0','SOC_init','EV1SOC_init','EV2SOC_init'}, 0);
    socmin = getf(evList(i), {'SOCMin','SOC_min','EV1SOC_min','EV2SOC_min'}, 0);
    socmax = getf(evList(i), {'SOCMax','SOC_max','EV1SOC_max','EV2SOC_max'}, 100);
    Ta     = getf(evList(i), {'Arrival','Ta','Ta1','Ta2'}, 0);
    Td     = getf(evList(i), {'Departure','Td','Td1','Td2'}, Num_var*t);
    soct   = getf(evList(i), {'SOCTarget','SOCT','EV1_SOCT','EV2_SOCT','TargetSOC','TargetSoC'}, soc0);

    if lockToInit
        soct = soc0;
    end

    Ta_idx = local_timeToIdx(Ta, t, Num_var);
    Td_idx = local_timeToIdx(Td, t, Num_var);
    if Td_idx < Ta_idx
        tmp = Ta_idx;
        Ta_idx = Td_idx;
        Td_idx = tmp;
    end

    col_dis0 = startCol0 + (i-1)*2*Num_var;
    col_chg0 = col_dis0 + Num_var;

    Kdis = (t*100/cap) * Ttri / eff;
    Kchg = (t*100/cap) * Ttri * eff;

    Amax = zeros(Num_var, totalCols);
    Amax(:, col_dis0+1:col_dis0+Num_var) = -Kdis;
    Amax(:, col_chg0+1:col_chg0+Num_var) = -Kchg;
    bmax = (-soc0 + socmax) * ones(Num_var,1);

    Amin = zeros(Num_var, totalCols);
    Amin(:, col_dis0+1:col_dis0+Num_var) = Kdis;
    Amin(:, col_chg0+1:col_chg0+Num_var) = Kchg;
    bmin = (soc0 - socmin) * ones(Num_var,1);

    row = zeros(1,totalCols);
    row(col_dis0+1:col_dis0+Num_var) = (t*100/cap) * Ttri(Td_idx,:) / eff;
    row(col_chg0+1:col_chg0+Num_var) = (t*100/cap) * Ttri(Td_idx,:) * eff;
    Atgt = row;
    btgt = soc0 - soct;

    A = [A; Amax; Amin; Atgt];
    b = [b; bmax; bmin; btgt];
end

SOCmat = nan(Num_var,N);
end

function v = local_getFieldNumeric(s, keys, def)
% Read a numeric field using the first matching key.
v = def;
for k = 1:numel(keys)
    key = keys{k};
    if isfield(s, key)
        try
            vv = s.(key);
            if isa(vv,'matlab.ui.control.NumericEditField')
                vv = vv.Value;
            end
            vv = double(vv);
            if ~isnan(vv)
                v = vv;
                return;
            end
        catch
        end
    end
end
end

function idx = local_timeToIdx(val, t, Num_var)
% Match the single-EV time conversion used elsewhere in the project.
try
    v = double(val);
catch
    v = val;
end

if isempty(v) || isnan(v)
    idx = 1;
    return;
end

idx = round(v / t);
idx = max(1, min(Num_var, idx));
end

function names = local_makeNames(sideTag, N)
% Build EV names for plotting and reporting.
names = cell(N,1);
if strcmpi(sideTag,'AC')
    pref = 'EV_AC';
else
    pref = 'EV_DC';
end

for i = 1:N
    names{i} = sprintf('%s%d', pref, i);
end
end
