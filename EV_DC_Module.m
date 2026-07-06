function [EDC_lb, EDC_ub, EDC_A, EDC_b, EV2SOC_init, EVP] = EV_DC_Module(t, Num_var, Eff_EV2, P_EV2_max, EV_CAP2, EV2SOC_init, EV2SOC_min, EV2SOC_max, Ta2, Td2, EV2_SOCT, Grid_status, ILC_status, EV_DC_status, preBlocks, postBlocks)
% DC-side EV bounds and SOC constraints.

if iscell(Ta2), Ta2 = Ta2{1}; end
if iscell(Td2), Td2 = Td2{1}; end
if isstring(Ta2) || ischar(Ta2), Ta2 = str2double(Ta2); end
if isstring(Td2) || ischar(Td2), Td2 = str2double(Td2); end
if isempty(Ta2) || isnan(Ta2), Ta2 = 0; end
if isempty(Td2) || isnan(Td2), Td2 = 24; end

if ~isscalar(t)
    t = 0.25;
end

Ta2 = round(Ta2 ./ t);
Td2 = round(Td2 ./ t);

Ta2 = max(1, min(Num_var, Ta2));
Td2 = max(1, min(Num_var, Td2));

if Td2 < Ta2
    Td2 = Num_var;
end

EVP = ones(Num_var, 1);
EVP(1:Ta2-1) = 0;
EVP(Td2+1:end) = 0;

lb1 = zeros(Num_var, 1);        % discharge
lb2 = -P_EV2_max * EVP;         % charge
ub1 = P_EV2_max * EVP;          % discharge
ub2 = zeros(Num_var, 1);        % charge

if EV_DC_status == 0 || EV_CAP2 == 0
    lb2 = zeros(Num_var, 1);
    ub1 = zeros(Num_var, 1);
    EV2SOC_init = 0;
    EV2SOC_min = 0;
    EV2_SOCT = 0;
    EV_CAP2 = 1;
end

if Grid_status == 0 || ILC_status == 0
    EV2_SOCT = EV2SOC_init;
end

EDC_lb = [lb1; lb2];
EDC_ub = [ub1; ub2];

% Wind curtailment shifts the EV block placement on the DC side.
A1 = -[zeros(Num_var,Num_var*preBlocks), (t*100/EV_CAP2)*tril(ones(Num_var))/Eff_EV2, (t*100/EV_CAP2)*tril(ones(Num_var))*Eff_EV2, zeros(Num_var,Num_var*postBlocks)];
b1 = (-EV2SOC_init + EV2SOC_max)*ones(Num_var,1);

A2 = [zeros(Num_var,Num_var*preBlocks), (t*100/EV_CAP2)*tril(ones(Num_var))/Eff_EV2, (t*100/EV_CAP2)*tril(ones(Num_var))*Eff_EV2, zeros(Num_var,Num_var*postBlocks)];
b2 = (EV2SOC_init - EV2SOC_min)*ones(Num_var,1);

time_window = tril(ones(Num_var));
time_window(1:Td2-1, :) = 0;
time_window(Td2+1:end, :) = 0;

EVT = ones(Num_var, 1);
EVT(1:Td2-1) = 0;
EVT(Td2+1:end) = 0;

A3 = [zeros(Num_var,Num_var*preBlocks), (t*100/EV_CAP2)*time_window/Eff_EV2, (t*100/EV_CAP2)*time_window*Eff_EV2, zeros(Num_var,Num_var*postBlocks)];
b3 = (EV2SOC_init - EV2_SOCT) .* EVT;

EDC_A = [A1; A2; A3];
EDC_b = [b1; b2; b3];
end
