function [S_mt, C_lb, C_ub, C_A, C_b] = MT_DC_Module(alpha, beta, gamma, M_Power, Num_var, MT_status, preBlocks)
% DC-side microturbine piecewise model.

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
    lb1 = zeros(Num_var,1); ub1 = ones(Num_var,1);  % commitment
    lb2 = zeros(Num_var,1); ub2 = P_piece_max*ones(Num_var,1);
    lb3 = zeros(Num_var,1); ub3 = P_piece_max*ones(Num_var,1);
    lb4 = zeros(Num_var,1); ub4 = P_piece_max*ones(Num_var,1);
    lb5 = zeros(Num_var,1); ub5 = P_piece_max*ones(Num_var,1);
    lb6 = zeros(Num_var,1); ub6 = P_piece_max*ones(Num_var,1);
    lb7 = zeros(Num_var,1); ub7 = P_piece_max*ones(Num_var,1);
    lb8 = zeros(Num_var,1); ub8 = P_piece_max*ones(Num_var,1);
    lb9 = zeros(Num_var,1); ub9 = P_piece_max*ones(Num_var,1);
    lb10 = zeros(Num_var,1); ub10 = P_piece_max*ones(Num_var,1);
    lb11 = zeros(Num_var,1); ub11 = P_piece_max*ones(Num_var,1);
else
    lb1 = zeros(Num_var,1); ub1 = ones(Num_var,1);  % commitment
    lb2 = zeros(Num_var,1); ub2 = zeros(Num_var,1);
    lb3 = zeros(Num_var,1); ub3 = zeros(Num_var,1);
    lb4 = zeros(Num_var,1); ub4 = zeros(Num_var,1);
    lb5 = zeros(Num_var,1); ub5 = zeros(Num_var,1);
    lb6 = zeros(Num_var,1); ub6 = zeros(Num_var,1);
    lb7 = zeros(Num_var,1); ub7 = zeros(Num_var,1);
    lb8 = zeros(Num_var,1); ub8 = zeros(Num_var,1);
    lb9 = zeros(Num_var,1); ub9 = zeros(Num_var,1);
    lb10 = zeros(Num_var,1); ub10 = zeros(Num_var,1);
    lb11 = zeros(Num_var,1); ub11 = zeros(Num_var,1);
end

C_lb = [lb1; lb2; lb3; lb4; lb5; lb6; lb7; lb8; lb9; lb10; lb11];
C_ub = [ub1; ub2; ub3; ub4; ub5; ub6; ub7; ub8; ub9; ub10; ub11];

% Place the MT block after the existing decision blocks.
A5 = [zeros(Num_var,Num_var*preBlocks), -eye(Num_var), ...
      eye(Num_var)/P_piece_max/pieces, eye(Num_var)/P_piece_max/pieces, ...
      eye(Num_var)/P_piece_max/pieces, eye(Num_var)/P_piece_max/pieces, ...
      eye(Num_var)/P_piece_max/pieces, eye(Num_var)/P_piece_max/pieces, ...
      eye(Num_var)/P_piece_max/pieces, eye(Num_var)/P_piece_max/pieces, ...
      eye(Num_var)/P_piece_max/pieces, eye(Num_var)/P_piece_max/pieces];

C_A = A5;
C_b = zeros(Num_var,1);
end
