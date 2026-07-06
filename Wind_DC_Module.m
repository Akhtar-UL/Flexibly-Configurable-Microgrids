function P_Wind2 = Wind_DC_Module(Num_var, P_Wind2, Wind2_Max, Wind_DC_status)
% DC-side wind profile.

if Wind_DC_status == 0
    P_Wind2 = zeros(Num_var,1);
else
    P_Wind2 = P_Wind2 .* Wind2_Max;
end
end
