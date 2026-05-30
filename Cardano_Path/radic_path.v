module radic_path (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] q, delta, offset, // Truyền trực tiếp delta đã tính từ Top
    
    output wire        out_valid,
    output wire [31:0] x1
);
    // 1. Tính -q/2 (Trễ 2)
    wire [31:0] neg_q; fp_neg u_neg_q (.in_operand_A(q), .out_result(neg_q));
    wire [31:0] neg_q_half; wire v1;
    fp_add_const #(.FLOAT_CONST(32'h3F000000)) u_mul_half (.clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_operand_A(neg_q), .out_valid(v1), .out_result(neg_q_half));

    // 2. Căn bậc hai Delta (Trễ 18)
    wire [31:0] sqrt_d; wire v2;
    fp_sqrt u_sqrt_d (.clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_operand_A(delta), .out_valid(v2), .out_result(sqrt_d));

    // Lùi q/2 chờ căn Delta
    wire [31:0] q_half_dly; wire v_q_half;
    shift_reg #(.W(32), .D(16)) dly_q (.clk(clk), .in(neg_q_half), .out(q_half_dly));
    shift_reg #(.W(1), .D(16))  dv_q  (.clk(clk), .in(v1), .out(v_q_half));

    // 3. Cộng trừ: u_in = -q/2 + sqrt(D), v_in = -q/2 - sqrt(D) (Trễ 4)
    wire [31:0] u_in, v_in; wire v3_u, v3_v;
    fp_add_sub u_add_u (.clk(clk), .rst_n(rst_n), .in_valid(v2 & v_q_half), .in_is_sub(1'b0), .in_operand_A(q_half_dly), .in_operand_B(sqrt_d), .out_valid(v3_u), .out_result(u_in));
    fp_add_sub u_sub_v (.clk(clk), .rst_n(rst_n), .in_valid(v2 & v_q_half), .in_is_sub(1'b1), .in_operand_A(q_half_dly), .in_operand_B(sqrt_d), .out_valid(v3_v), .out_result(v_in));

    // 4. Khai căn bậc 3: u = cbrt(u_in), v = cbrt(v_in) (Trễ 20)
    wire [31:0] u_out, v_out; wire v4_u, v4_v;
    fp_cbrt u_cbrt_u (.clk(clk), .rst_n(rst_n), .in_valid(v3_u), .in_operand_A(u_in), .out_valid(v4_u), .out_result(u_out));
    fp_cbrt u_cbrt_v (.clk(clk), .rst_n(rst_n), .in_valid(v3_v), .in_operand_A(v_in), .out_valid(v4_v), .out_result(v_out));

    // 5. Cộng: u + v (Trễ 4)
    wire [31:0] uv_sum; wire v5;
    fp_add_sub u_add_uv (.clk(clk), .rst_n(rst_n), .in_valid(v4_u & v4_v), .in_is_sub(1'b0), .in_operand_A(u_out), .in_operand_B(v_out), .out_valid(v5), .out_result(uv_sum));

    // Match delay cho offset (Trễ = 2 + 18 + 4 + 20 + 4 = 48)
    wire [31:0] offset_dly;
    shift_reg #(.W(32), .D(48)) dly_off (.clk(clk), .in(offset), .out(offset_dly));

    // 6. Trừ offset: x1 = u + v - offset (Trễ 4)
    fp_add_sub u_sub_off (.clk(clk), .rst_n(rst_n), .in_valid(v5), .in_is_sub(1'b1), .in_operand_A(uv_sum), .in_operand_B(offset_dly), .out_valid(out_valid), .out_result(x1));

endmodule