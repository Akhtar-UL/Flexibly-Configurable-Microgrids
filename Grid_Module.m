function [G_lb, G_ub] = Grid_Module(Num_var, P_grid_max, P_CL1, P_NL1, P_CL2, P_NL2, P_PV1, P_PV2, P_Wind1, P_Wind2, Grid_status, ILC_status)
% Grid exchange, shedding, and curtailment bounds.

lb1 = zeros(Num_var,1);             % grid buy
lb2 = -P_grid_max*ones(Num_var,1);  % grid sell
lb3 = zeros(Num_var,1);             % AC critical shedding
lb4 = zeros(Num_var,1);             % AC non-critical shedding
lb5 = zeros(Num_var,1);             % DC critical shedding
lb6 = zeros(Num_var,1);             % DC non-critical shedding
lb7 = zeros(Num_var,1);             % AC PV curtailment
lb8 = zeros(Num_var,1);             % DC PV curtailment
lb9 = zeros(Num_var,1);             % AC wind curtailment
lb10 = zeros(Num_var,1);            % DC wind curtailment

ub1 = P_grid_max*ones(Num_var,1);   % grid buy
ub2 = zeros(Num_var,1);             % grid sell
ub3 = max(P_CL1, 0);                % AC critical shedding
ub4 = max(P_NL1, 0);                % AC non-critical shedding
ub5 = max(P_CL2, 0);                % DC critical shedding
ub6 = max(P_NL2, 0);                % DC non-critical shedding
ub7 = max(P_PV1, 0);                % AC PV curtailment
ub8 = max(P_PV2, 0);                % DC PV curtailment
ub9 = max(P_Wind1, 0);              % AC wind curtailment
ub10 = max(P_Wind2, 0);             % DC wind curtailment

if Grid_status == 0 || P_grid_max == 0
    lb2 = zeros(Num_var,1);
    ub1 = zeros(Num_var,1);
    ub2 = zeros(Num_var,1);
end

if ILC_status == 0
    % Converter isolation is handled in the converter module.
end

G_lb = [lb1; lb2; lb3; lb4; lb5; lb6; lb7; lb8; lb9; lb10];
G_ub = [ub1; ub2; ub3; ub4; ub5; ub6; ub7; ub8; ub9; ub10];
end
