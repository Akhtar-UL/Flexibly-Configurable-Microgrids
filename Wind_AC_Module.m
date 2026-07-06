function P_Wind1 = Wind_AC_Module(Num_var, P_Wind1, Wind1_Max, Wind_AC_status)
% AC-side wind profile.

if Wind_AC_status == 0
    P_Wind1 = zeros(Num_var,1);
else
    P_Wind1 = P_Wind1 .* Wind1_Max;
end
end
