function [S_diesel, C_lb, C_ub, C_A, C_b] = CDG_Module(alpha, beta, gamma, M_Power, Num_var, CDG_status)
% Piecewise diesel generator model.

GalToLiter = 3.785412;
Price_diesel = 1200;

if M_Power == 0
    M_Power = 0.001;
end

pieces = 10;
F_cost = @(Power_diesel) alpha + beta*Power_diesel + gamma*Power_diesel^2;
P_diesel_max = M_Power;
P_piece_max = P_diesel_max / pieces;

S_diesel = zeros(pieces,1);
for a = 1:pieces
    S_diesel(a) = (F_cost(P_piece_max*a) - F_cost(P_piece_max*(a - 1))) / P_piece_max;
end

lb1 = zeros(Num_var,1);   % commitment
lb2 = zeros(Num_var,1);
lb3 = zeros(Num_var,1);
lb4 = zeros(Num_var,1);
lb5 = zeros(Num_var,1);
lb6 = zeros(Num_var,1);
lb7 = zeros(Num_var,1);
lb8 = zeros(Num_var,1);
lb9 = zeros(Num_var,1);
lb10 = zeros(Num_var,1);
lb11 = zeros(Num_var,1);

ub1 = ones(Num_var,1);                  % commitment
ub2 = P_piece_max*ones(Num_var,1);
ub3 = P_piece_max*ones(Num_var,1);
ub4 = P_piece_max*ones(Num_var,1);
ub5 = P_piece_max*ones(Num_var,1);
ub6 = P_piece_max*ones(Num_var,1);
ub7 = P_piece_max*ones(Num_var,1);
ub8 = P_piece_max*ones(Num_var,1);
ub9 = P_piece_max*ones(Num_var,1);
ub10 = P_piece_max*ones(Num_var,1);
ub11 = P_piece_max*ones(Num_var,1);

if CDG_status == 0 || M_Power == 0
    lb1 = zeros(Num_var,1);
    ub1 = zeros(Num_var,1);
    ub2 = zeros(Num_var,1);
    ub3 = zeros(Num_var,1);
    ub4 = zeros(Num_var,1);
    ub5 = zeros(Num_var,1);
    ub6 = zeros(Num_var,1);
    ub7 = zeros(Num_var,1);
    ub8 = zeros(Num_var,1);
    ub9 = zeros(Num_var,1);
    ub10 = zeros(Num_var,1);
    ub11 = zeros(Num_var,1);
end

C_lb = [lb1; lb2; lb3; lb4; lb5; lb6; lb7; lb8; lb9; lb10; lb11];
C_ub = [ub1; ub2; ub3; ub4; ub5; ub6; ub7; ub8; ub9; ub10; ub11];

A5 = [zeros(Num_var,Num_var*10), -eye(Num_var), ...
      eye(Num_var)/P_piece_max/pieces, eye(Num_var)/P_piece_max/pieces, ...
      eye(Num_var)/P_piece_max/pieces, eye(Num_var)/P_piece_max/pieces, ...
      eye(Num_var)/P_piece_max/pieces, eye(Num_var)/P_piece_max/pieces, ...
      eye(Num_var)/P_piece_max/pieces, eye(Num_var)/P_piece_max/pieces, ...
      eye(Num_var)/P_piece_max/pieces, eye(Num_var)/P_piece_max/pieces, ...
      zeros(Num_var,Num_var*10)];
b5 = zeros(Num_var,1);

C_A = A5;
C_b = b5;
end
