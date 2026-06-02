`timescale 1ns / 1ps

module fp_acos #(
    parameter STAGES = 35
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output wire        out_valid, 
    output wire [31:0] out_result
);
    // =========================================================================
    // BỘ HỆ SỐ ABRAMOWITZ & STEGUN CHO ACOS (Minimax tối ưu cho đa thức bậc 3)
    // =========================================================================
    localparam N3 = 32'hBC996C25; // -0.0187293
    localparam N2 = 32'h3D9814C4; //  0.0742610
    localparam N1 = 32'hBE593452; // -0.2121144
    localparam N0 = 32'h3FC90E2A; //  1.5707288

    // =========================================================================
    // T = 0 -> 1: Lưu giá trị tuyệt đối |x| và Bắt điểm kỳ dị (Special Cases)
    // =========================================================================
    wire [31:0] x_abs = {1'b0, in_operand_A[30:0]};
    
    // Nhận diện các điểm gây sai số cực lớn để MUX trực tiếp phần cứng
    wire is_plus_1  = (in_operand_A == 32'h3F800000); // x = 1.0
    wire is_minus_1 = (in_operand_A == 32'hBF800000); // x = -1.0
    wire is_zero    = (in_operand_A == 32'h00000000) || (in_operand_A == 32'h80000000); // x = 0.0 hoặc -0.0
    
    reg [31:0] x_d1; 
    reg        s_d1, v_d1;
    reg        is_p1_d1, is_m1_d1, is_z_d1;

    always @(posedge clk or negedge rst_n) begin 
        if (!rst_n) begin
            v_d1 <= 1'b0;
        end else begin
            x_d1     <= x_abs; 
            s_d1     <= in_operand_A[31]; 
            v_d1     <= in_valid; 
            is_p1_d1 <= is_plus_1;
            is_m1_d1 <= is_minus_1;
            is_z_d1  <= is_zero;
        end
    end

    // =========================================================================
    // T = 1 -> 5: Tính sub_x = 1.0 - |x|
    // =========================================================================
    wire [31:0] sub_x; 
    wire        v_sub;
    
    fp_add_sub u_sub (
        .clk(clk), .rst_n(rst_n), .in_valid(v_d1), .in_is_sub(1'b1),
        .in_operand_A(32'h3F800000), .in_operand_B(x_d1),
        .out_valid(v_sub), .out_result(sub_x),
        .status_overflow(), .status_invalid(), .status_zero()
    );

    // =========================================================================
    // T = 5 -> 23: Tính sqrt_x = sqrt(1.0 - |x|)
    // =========================================================================
    wire [31:0] sqrt_x; 
    wire        v_sqrt;
    
    fp_sqrt u_sqrt (
        .clk(clk), .rst_n(rst_n), .in_valid(v_sub),
        .in_operand_A(sub_x[31] ? 32'd0 : sub_x), // Clamp an toàn tránh số âm
        .out_valid(v_sqrt), .out_result(sqrt_x), .status_invalid()
    );

    // =========================================================================
    // SONG SONG T = 1 -> 16: Tính P(x) = ((N3*x + N2)*x + N1)*x + N0
    // =========================================================================
    wire [31:0] tn1, tn2, px; 
    wire        v_n1, v_n2, v_px;
    
    fp_fma u_fma1 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_d1),
        .in_operand_A(N3), .in_operand_B(x_d1), .in_operand_C(N2),
        .out_valid(v_n1), .out_result(tn1),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    
    wire [31:0] x_d6; 
    shift_reg #(.W(32), .D(5)) dx6 (.clk(clk), .in(x_d1), .out(x_d6));

    fp_fma u_fma2 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_n1),
        .in_operand_A(tn1), .in_operand_B(x_d6), .in_operand_C(N1),
        .out_valid(v_n2), .out_result(tn2),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );
    
    wire [31:0] x_d11; 
    shift_reg #(.W(32), .D(5)) dx11 (.clk(clk), .in(x_d6), .out(x_d11));

    fp_fma u_fma3 (
        .clk(clk), .rst_n(rst_n), .in_valid(v_n2),
        .in_operand_A(tn2), .in_operand_B(x_d11), .in_operand_C(N0),
        .out_valid(v_px), .out_result(px),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // =========================================================================
    // T = 16 -> 23: Delay P(x) chờ SQRT
    // =========================================================================
    wire [31:0] px_d23;
    shift_reg #(.W(32), .D(7)) dpx (.clk(clk), .in(px), .out(px_d23));

    // =========================================================================
    // T = 23 -> 27: Nhân acos_abs = sqrt_x * P(x)
    // =========================================================================
    wire [31:0] acos_abs; 
    wire        v_acos;
    
    fp_mul u_mul_acos (
        .clk(clk), .rst_n(rst_n), .in_valid(v_sqrt),
        .in_operand_A(sqrt_x), .in_operand_B(px_d23),
        .out_valid(v_acos), .out_result(acos_abs),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // =========================================================================
    // T = 27 -> 30: Delay đồng bộ để khớp chu kỳ FMA bù góc
    // =========================================================================
    wire [31:0] acos_abs_d30; 
    wire        v_d30;
    
    shift_reg #(.W(32), .D(3)) dacos (.clk(clk), .in(acos_abs), .out(acos_abs_d30));
    shift_reg #(.W(1),  .D(3)) dv30  (.clk(clk), .in(v_acos),   .out(v_d30));

    // =========================================================================
    // T = 30 -> 35: Tính góc bù nếu x < 0: result = (-1.0 * acos_abs) + PI
    // PI chính xác chuẩn IEEE-754 = 32'h40490FDB
    // =========================================================================
    wire [31:0] fma_adjust; 
    wire        v_fma;
    
    fp_fma u_fma_quad (
        .clk(clk), .rst_n(rst_n), .in_valid(v_d30), 
        .in_operand_A(32'hBF800000), .in_operand_B(acos_abs_d30), .in_operand_C(32'h40490FDB), 
        .out_valid(v_fma), .out_result(fma_adjust),
        .status_overflow(), .status_underflow(), .status_invalid(), .status_zero()
    );

    // =========================================================================
    // DELAY TÍN HIỆU ĐIỀU KHIỂN XUỐNG T = 35
    // =========================================================================
    wire [31:0] acos_dly35;
    shift_reg #(.W(32), .D(5))  d_fin_acos (.clk(clk), .in(acos_abs_d30), .out(acos_dly35));
    
    wire s_d35, is_p1_d35, is_m1_d35, is_z_d35;
    shift_reg #(.W(1),  .D(34)) ds35 (.clk(clk), .in(s_d1),     .out(s_d35));
    shift_reg #(.W(1),  .D(34)) dp35 (.clk(clk), .in(is_p1_d1), .out(is_p1_d35));
    shift_reg #(.W(1),  .D(34)) dm35 (.clk(clk), .in(is_m1_d1), .out(is_m1_d35));
    shift_reg #(.W(1),  .D(34)) dz35 (.clk(clk), .in(is_z_d1),  .out(is_z_d35));

    // =========================================================================
    // XUẤT KẾT QUẢ VỚI BOUNDARY BYPASS (KHÔNG TỐN CYCLE MÀ VẪN TRIỆT ĐỂ)
    // =========================================================================
    assign out_valid = v_fma;
    
    wire [31:0] normal_calc = s_d35 ? fma_adjust : acos_dly35;
    
    // MUX trả về giá trị Perfect ULP cho các điểm kỳ dị
    assign out_result = is_p1_d35 ? 32'h00000000 : // acos(1.0)  = 0.0
                        is_m1_d35 ? 32'h40490FDB : // acos(-1.0) = PI
                        is_z_d35  ? 32'h3FC90FDB : // acos(0.0)  = PI/2 (Sửa lỗi N0 không chính xác)
                        normal_calc;

endmodule