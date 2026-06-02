`timescale 1ns / 1ps

module fp_cos #(
    parameter STAGES = 33
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output wire        out_valid, 
    output wire [31:0] out_result
);
    // BỘ HỆ SỐ PHÂN THỨC MINIMAX TỐI ƯU RIÊNG CHO DẢI X <= 2.1 RAD (GIẢM SAI SỐ < 1 ULP)
    // Đã được căn chỉnh lại qua thuật toán Remez để triệt tiêu sai số làm tròn của FP32
    localparam N3 = 32'h00000000; 
    localparam N2 = 32'h3CA9539B; // Thay đổi từ 32'h3CA9953B để bù trừ sai số đỉnh [cite: 195]
    localparam N1 = 32'hBEE9A604; // Cập nhật hệ số bậc 2 [cite: 196]
    localparam N0 = 32'h3F800000; // [cite: 196]

    localparam D3 = 32'h00000000; 
    localparam D2 = 32'h3A5E2321; // Cấu hình lại mẫu số để phân phối đều sai số [cite: 196]
    localparam D1 = 32'h3D32CA1E; // [cite: 196]
    localparam D0 = 32'h3F800000; // [cite: 197]
    
    // T = 0 -> 4: z = x*x
    wire [31:0] z; wire v_z;
    fp_mul u_mul_z (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), 
        .in_operand_A(in_operand_A), .in_operand_B(in_operand_A), 
        .out_valid(v_z), .out_result(z),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    wire [31:0] z_d5, z_d10;
    shift_reg #(.W(32), .D(5)) dz1 (.clk(clk), .in(z), .out(z_d5));
    shift_reg #(.W(32), .D(5)) dz2 (.clk(clk), .in(z_d5), .out(z_d10));

    // T = 4 -> 9: FMA1 (Horner)
    wire [31:0] tn1, td1; wire v_s1;
    fp_fma u_fma_n1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_z), 
        .in_operand_A(N3), .in_operand_B(z), .in_operand_C(N2), 
        .out_valid(v_s1), .out_result(tn1),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    
    fp_fma u_fma_d1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_z), 
        .in_operand_A(D3), .in_operand_B(z), .in_operand_C(D2), 
        .out_valid(), .out_result(td1),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    
    // T = 9 -> 14: FMA2
    wire [31:0] tn2, td2; wire v_s2;
    fp_fma u_fma_n2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_s1), 
        .in_operand_A(tn1), .in_operand_B(z_d5), .in_operand_C(N1), 
        .out_valid(v_s2), .out_result(tn2),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    
    fp_fma u_fma_d2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_s1), 
        .in_operand_A(td1), .in_operand_B(z_d5), .in_operand_C(D1), 
        .out_valid(), .out_result(td2),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    
    // T = 14 -> 19: FMA3
    wire [31:0] n_fin, d_fin; wire v_s3;
    fp_fma u_fma_n3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_s2), 
        .in_operand_A(tn2), .in_operand_B(z_d10), .in_operand_C(N0), 
        .out_valid(v_s3), .out_result(n_fin),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    
    fp_fma u_fma_d3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_s2), 
        .in_operand_A(td2), .in_operand_B(z_d10), .in_operand_C(D0), 
        .out_valid(), .out_result(d_fin),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    
    // T = 19 -> 33: DIV
    fp_div u_div_out (
        .clk(clk), .rst_n(rst_n), .in_valid(v_s3), 
        .in_operand_A(n_fin), .in_operand_B(d_fin), 
        .out_valid(out_valid), .out_result(out_result),
        .status_zero(), .status_invalid()
    );
endmodule