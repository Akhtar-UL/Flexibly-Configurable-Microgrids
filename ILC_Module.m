function [I_lb, I_ub] = ILC_Module(Num_var, Eff_conv, P_conv_max, ILC_status)
% Converter power bounds.

lb1 = zeros(Num_var,1);             % AC to DC
lb2 = -P_conv_max*ones(Num_var,1);  % DC to AC

ub1 = P_conv_max*ones(Num_var,1);   % AC to DC
ub2 = zeros(Num_var,1);             % DC to AC

if ILC_status == 0 || P_conv_max == 0
    lb2 = zeros(Num_var,1);
    ub1 = zeros(Num_var,1);
end

I_lb = [lb1; lb2];
I_ub = [ub1; ub2];
end
