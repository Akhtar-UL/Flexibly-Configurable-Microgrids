function [S_mt, C_lb, C_ub, C_A, C_b] = MT_AC_Module(alpha, beta, gamma, M_Power, Num_var, MT_status, preBlocks)
% AC-side microturbine piecewise model.

if nargin < 7
    error('MT_AC_Module requires 7 inputs.');
end
if nargin < 8
    preBlocks = 10;
end

if M_Power == 0
    M_Power = 0.001;
end

pieces = 10;
F_cost = @(P) alpha + beta*P + gamma*P^2;
P_mt_max = M_Power;
P_piece_max = P_mt_max / pieces;

S_mt = zeros(pieces,1);
for a = 1:pieces
    S_mt(a) = (F_cost(P_piece_max*a) - F_cost(P_piece_max*(a - 1))) / P_piece_max;
end

if MT_status == 1
    lb1 = zeros(Num_var,1);         % commitment
    ub1 = ones(Num_var,1);          % commitment
    lbp = zeros(Num_var,1);
    ubp = P_piece_max*ones(Num_var,1);
else
    lb1 = zeros(Num_var,1);         % commitment
    ub1 = ones(Num_var,1);          % commitment
    lbp = zeros(Num_var,1);
    ubp = zeros(Num_var,1);
end

C_lb = [lb1; repmat(lbp, pieces, 1)];
C_ub = [ub1; repmat(ubp, pieces, 1)];

% Couple the commitment variable with the piecewise power blocks.
A5 = [zeros(Num_var, Num_var*preBlocks), -eye(Num_var), ...
      repmat(eye(Num_var)/P_piece_max/pieces, 1, pieces)];

C_A = A5;
C_b = zeros(Num_var,1);
end
