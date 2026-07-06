function [EAC_lb, EAC_ub, EAC_A, EAC_b, EV1SOC_init, EVP] = EV_AC_Module(t, Num_var, Eff_EV1, P_EV1_max, EV_CAP1, EV1SOC_init, EV1SOC_min, EV1SOC_max, Ta1, Td1, EV1_SOCT, Grid_status, EV_AC_status, preBlocks, postBlocks)
% AC-side EV bounds and SOC constraints.

Ta1 = Ta1 / t;
Td1 = Td1 / t;

EVP = ones(Num_var, 1);
EVP(1:Ta1-1) = 0;
EVP(Td1+1:end) = 0;

lb1 = zeros(Num_var, 1);        % discharge
lb2 = -P_EV1_max * EVP;         % charge
ub1 = P_EV1_max * EVP;          % discharge
ub2 = zeros(Num_var, 1);        % charge

if EV_AC_status == 0 || EV_CAP1 == 0
    lb2 = zeros(Num_var, 1);
    ub1 = zeros(Num_var, 1);
    EV1SOC_init = 0;
    EV1SOC_min = 0;
    EV1_SOCT = 0;
    EV_CAP1 = 1;
end

if Grid_status == 0
    EV1_SOCT = EV1SOC_init;
end

EAC_lb = [lb1; lb2];
EAC_ub = [ub1; ub2];

A1 = -[zeros(Num_var,Num_var*preBlocks), (t*100/EV_CAP1)*tril(ones(Num_var))/Eff_EV1, (t*100/EV_CAP1)*tril(ones(Num_var))*Eff_EV1, zeros(Num_var,Num_var*postBlocks)];
b1 = (-EV1SOC_init + EV1SOC_max)*ones(Num_var,1);

A2 = [zeros(Num_var,Num_var*preBlocks), (t*100/EV_CAP1)*tril(ones(Num_var))/Eff_EV1, (t*100/EV_CAP1)*tril(ones(Num_var))*Eff_EV1, zeros(Num_var,Num_var*postBlocks)];
b2 = (EV1SOC_init - EV1SOC_min)*ones(Num_var,1);

time_window = tril(ones(Num_var));
time_window(1:Td1-1, :) = 0;
time_window(Td1+1:end, :) = 0;

EVT = ones(Num_var, 1);
EVT(1:Td1-1) = 0;
EVT(Td1+1:end) = 0;

A3 = [zeros(Num_var,Num_var*preBlocks), (t*100/EV_CAP1)*time_window/Eff_EV1, (t*100/EV_CAP1)*time_window*Eff_EV1, zeros(Num_var,Num_var*postBlocks)];
b3 = (EV1SOC_init - EV1_SOCT) .* EVT;

EAC_A = [A1; A2; A3];
EAC_b = [b1; b2; b3];
end
