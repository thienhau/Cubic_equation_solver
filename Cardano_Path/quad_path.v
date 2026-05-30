module quad_path (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] b, c, d,
    
    output wire        out_valid,
    output wire [31:0] x1,
    output wire [31:0] x2
);
    // 1. Tính c^2 và b*d (Trễ 4)
    wire [31:0] c2, bd; wire v1_1, v1_2;
    fp_mul u_mul_c2 (.clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_operand_A(c), .in_operand_B(c), .out_valid(v1_1), .out_result(c2));
    fp_mul u_mul_bd (.clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_operand_A(b), .in_operand_B(d), .out_valid(v1_2), .out_result(bd));

    // 2. Tính 4bd và 2b (Trễ 2)
    wire [31:0] bd4, b2; wire v2_1, v2_2;
    fp_add_const #(.FLOAT_CONST(32'h40800000)) u_mul_4 (.clk(clk), .rst_n(rst_n), .in_valid(v1_2), .in_operand_A(bd), .out_valid(v2_1), .out_result(bd4));
    fp_add_const #(.FLOAT_CONST(32'h40000000)) u_mul_2 (.clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_operand_A(b), .out_valid(v2_2), .out_result(b2));
    
    // Delay match cho c2 và b2
    wire [31:0] c2_dly, b2_dly, c_dly; wire v2_c2, v2_b2;
    shift_reg #(.W(32), .D(2)) dly_c2 (.clk(clk), .in(c2), .out(c2_dly));
    shift_reg #(.W(32), .D(22)) dly_b2 (.clk(clk), .in(b2), .out(b2_dly)); // Chờ SQRT(18) + SUB(4) = 22
    shift_reg #(.W(32), .D(28)) dly_c  (.clk(clk), .in(c),  .out(c_dly));  // Chờ tổng (4+2+4+18)
    shift_reg #(.W(1), .D(2)) dv_c2 (.clk(clk), .in(v1_1), .out(v2_c2));

    // 3. Tính Delta = c^2 - 4bd (Trễ 4)
    wire [31:0] delta; wire v3;
    fp_add_sub u_sub_delta (.clk(clk), .rst_n(rst_n), .in_valid(v2_1 & v2_c2), .in_is_sub(1'b1), .in_operand_A(c2_dly), .in_operand_B(bd4), .out_valid(v3), .out_result(delta));

    // 4. Khai căn Delta (Trễ 18)
    wire [31:0] sqrt_delta; wire v4;
    fp_sqrt u_sqrt (.clk(clk), .rst_n(rst_n), .in_valid(v3), .in_operand_A(delta), .out_valid(v4), .out_result(sqrt_delta));

    // 5. Tính tử số: -c + sqrt_D và -c - sqrt_D (Trễ 4)
    wire [31:0] neg_c;
    fp_neg u_neg_c (.in_operand_A(c_dly), .out_result(neg_c));
    
    wire [31:0] num1, num2; wire v5_1, v5_2;
    fp_add_sub u_add_num1 (.clk(clk), .rst_n(rst_n), .in_valid(v4), .in_is_sub(1'b0), .in_operand_A(neg_c), .in_operand_B(sqrt_delta), .out_valid(v5_1), .out_result(num1));
    fp_add_sub u_sub_num2 (.clk(clk), .rst_n(rst_n), .in_valid(v4), .in_is_sub(1'b1), .in_operand_A(neg_c), .in_operand_B(sqrt_delta), .out_valid(v5_2), .out_result(num2));

    // 6. Chia cho 2b (Trễ 14)
    fp_div u_div_x1 (.clk(clk), .rst_n(rst_n), .in_valid(v5_1), .in_operand_A(num1), .in_operand_B(b2_dly), .out_valid(out_valid), .out_result(x1));
    fp_div u_div_x2 (.clk(clk), .rst_n(rst_n), .in_valid(v5_2), .in_operand_A(num2), .in_operand_B(b2_dly), .out_valid(), .out_result(x2));

endmodule