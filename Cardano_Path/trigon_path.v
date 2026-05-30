`timescale 1ns / 1ps

module trigon_path (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] p, q, offset,
    output wire        out_valid,
    output wire [31:0] x1, x2, x3
);
    // T=0 -> T=4: p_third = p * (-1/3)
    wire [31:0] p_third; wire v_p3;
    fp_mul mul_p3(clk, rst_n, in_valid, p, 32'hBEAAAAAB, v_p3, p_third);
    
    // T=4 -> T=22: val_2 = sqrt(p_third)
    wire [31:0] val_2; wire v_v2;
    fp_sqrt sq_v2(clk, rst_n, v_p3, p_third, v_v2, val_2);

    // T=0 -> T=4: num = q * 1.5
    wire [31:0] num; wire v_num;
    fp_mul mul_num(clk, rst_n, in_valid, q, 32'h3FC00000, v_num, num);
    
    // Đồng bộ p chờ val_2 (Đợi 22 chu kỳ) & num chờ denom
    wire [31:0] p_dly22, num_dly22;
    shift_reg #(32, 22) dp22(clk, p, p_dly22);
    shift_reg #(32, 22) dn22(clk, num, num_dly22);
    
    // T=22 -> T=26: denom = p * val_2
    wire [31:0] denom; wire v_den;
    fp_mul mul_den(clk, rst_n, v_v2, p_dly22, val_2, v_den, denom);

    // T=26 -> T=40: arg = num / denom
    wire [31:0] arg_val; wire v_arg;
    fp_div div_arg(clk, rst_n, v_den, num_dly22, denom, v_arg, arg_val);
    
    // T=40 -> T=74: theta = acos(arg)
    wire [31:0] theta; wire v_th;
    fp_acos u_acos(clk, rst_n, v_arg, arg_val, v_th, theta);

    // T=74 -> T=78: t1 = theta * (1/3)
    wire [31:0] t1; wire v_t1;
    fp_mul mul_t1(clk, rst_n, v_th, theta, 32'h3EAAAAAB, v_t1, t1);

    // T=78 -> T=82: t2 = t1 - 2PI/3 | t3 = t1 - 4PI/3
    wire [31:0] t2, t3; wire v_t2;
    fp_add_sub add_t2(clk, rst_n, v_t1, 1'b0, t1, 32'hC0060A92, v_t2, t2);
    fp_add_sub add_t3(clk, rst_n, v_t1, 1'b0, t1, 32'hC0860A92, , t3);
    
    // T=78 -> T=111: c1 = cos(t1)
    wire [31:0] c1; wire v_c1;
    fp_cos u_cos1(clk, rst_n, v_t1, t1, v_c1, c1);

    // T=82 -> T=115: c2 = cos(t2) | c3 = cos(t3)
    wire [31:0] c2, c3; wire v_c2;
    fp_cos u_cos2(clk, rst_n, v_t2, t2, v_c2, c2);
    fp_cos u_cos3(clk, rst_n, v_t2, t3, , c3);

    // Đồng bộ c1 trễ chờ c2, c3 (Đợi 115 - 111 = 4 chu kỳ)
    wire [31:0] c1_dly4;
    shift_reg #(32, 4) dc1(clk, c1, c1_dly4);

    // Tính r = 2 * val_2 (Bằng cách +1 Exponent), cần kéo trễ từ T=22 đến T=115 (93 cycles)
    wire [31:0] r = {val_2[31], val_2[30:23] + 8'd1, val_2[22:0]};
    wire [31:0] r_dly93; shift_reg #(32, 93) dr93(clk, r, r_dly93);
    
    // Đồng bộ offset từ T=0 đến T=115
    wire [31:0] off_dly115;
    shift_reg #(32, 115) doff(clk, offset, off_dly115);
    wire [31:0] neg_off = {~off_dly115[31], off_dly115[30:0]};
    
    // T=115 -> T=120: x = r * c + (-offset)
    fp_fma fma_x1(clk, rst_n, v_c2, r_dly93, c1_dly4, neg_off, out_valid, x1);
    fp_fma fma_x2(clk, rst_n, v_c2, r_dly93, c2, neg_off, , x2);
    fp_fma fma_x3(clk, rst_n, v_c2, r_dly93, c3, neg_off, , x3);
endmodule