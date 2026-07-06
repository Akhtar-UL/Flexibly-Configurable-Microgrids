function P_PV2 = PV_DC_Module(Num_var, P_PV2, PV2_Max, PV_DC_status)
% DC-side PV profile.

if PV_DC_status == 0
    P_PV2 = zeros(Num_var,1);
else
    P_PV2 = P_PV2 .* PV2_Max;
end
end
