function P_PV1 = PV_AC_Module(Num_var, P_PV1, PV1_Max, PV_AC_status)
% AC-side PV profile.

if PV_AC_status == 0
    P_PV1 = zeros(Num_var,1);
else
    P_PV1 = P_PV1 .* PV1_Max;
end
end
