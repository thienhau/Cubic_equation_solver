// ============================================================================
// MODULE 3: FP_ACOS (Arccosine)
// Phương pháp: Tính acos(x) qua Padé [3/3] trực tiếp (trong biến x).
// Gấp góc phần tư: acos(-x) = PI - acos(x). Ta tính acos(|x|) rồi FMA với PI.
// Số chu kỳ dự tính: 6 FMA (Horner) + 1 DIV + 1 FMA (Gấp góc) = 44 chu kỳ
// ============================================================================
module fp_acos (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    output reg         mul_req, output reg [31:0] mul_op_a, output reg [31:0] mul_op_b, input wire mul_ack, input wire [31:0] mul_result,    
    output reg         fma_req, output reg [31:0] fma_op_a, output reg [31:0] fma_op_b, output reg [31:0] fma_op_c, input wire fma_ack, input wire [31:0] fma_result,
    output reg         div_req, output reg [31:0] div_op_a, output reg [31:0] div_op_b, input wire div_ack, input wire [31:0] div_result,
    
    output reg         out_valid,
    output reg  [31:0] out_result,
    output reg         status_invalid
);

    // Hằng số Padé [3/3] cho acos
    localparam A_N3 = 32'hB2000000; localparam A_N2 = 32'h35000000; localparam A_N1 = 32'hBE000000; localparam A_N0 = 32'h3FC90FDB; // PI/2
    localparam A_D3 = 32'h31000000; localparam A_D2 = 32'h34000000; localparam A_D1 = 32'h3B000000; localparam A_D0 = 32'h3F800000; // 1.0
    
    localparam PI   = 32'h40490FDB;
    localparam NEG_ONE = 32'hBF800000; // -1.0

    reg [3:0] state;
    reg        sign_reg;
    reg [31:0] x_abs;
    reg [31:0] tn1, td1, tn2, td2, n_final, d_final;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 4'd0;
            out_valid <= 1'b0;
            mul_req <= 0; fma_req <= 0; div_req <= 0;
        end else begin
            out_valid <= 1'b0;
            case (state)
                4'd0: begin
                    if (in_valid) begin
                        // Check logic miền giá trị [-1, 1] (Làm tròn exception)
                        if (in_operand_A[30:23] >= 8'd127 && in_operand_A[22:0] != 0) begin
                            out_valid <= 1'b1;
                            out_result <= {1'b1, 8'hFF, 23'd1}; // NaN
                            status_invalid <= 1'b1;
                        end else begin
                            sign_reg <= in_operand_A[31];
                            x_abs    <= {1'b0, in_operand_A[30:0]};
                            state    <= 4'd1;
                        end
                    end
                end
                
                4'd1: begin // FMA: tn1 = n3 * x + n2
                    if (fma_ack) begin tn1 <= fma_result; fma_req <= 1'b0; state <= 4'd2; end 
                    else begin fma_req <= 1'b1; fma_op_a <= A_N3; fma_op_b <= x_abs; fma_op_c <= A_N2; end
                end
                
                4'd2: begin // FMA: td1 = d3 * x + d2
                    if (fma_ack) begin td1 <= fma_result; fma_req <= 1'b0; state <= 4'd3; end 
                    else begin fma_req <= 1'b1; fma_op_a <= A_D3; fma_op_b <= x_abs; fma_op_c <= A_D2; end
                end
                
                4'd3: begin // FMA: tn2 = tn1 * x + n1
                    if (fma_ack) begin tn2 <= fma_result; fma_req <= 1'b0; state <= 4'd4; end 
                    else begin fma_req <= 1'b1; fma_op_a <= tn1; fma_op_b <= x_abs; fma_op_c <= A_N1; end
                end
                
                4'd4: begin // FMA: td2 = td1 * x + d1
                    if (fma_ack) begin td2 <= fma_result; fma_req <= 1'b0; state <= 4'd5; end 
                    else begin fma_req <= 1'b1; fma_op_a <= td1; fma_op_b <= x_abs; fma_op_c <= A_D1; end
                end
                
                4'd5: begin // FMA: N = tn2 * x + n0
                    if (fma_ack) begin n_final <= fma_result; fma_req <= 1'b0; state <= 4'd6; end 
                    else begin fma_req <= 1'b1; fma_op_a <= tn2; fma_op_b <= x_abs; fma_op_c <= A_N0; end
                end
                
                4'd6: begin // FMA: D = td2 * x + d0
                    if (fma_ack) begin d_final <= fma_result; fma_req <= 1'b0; state <= 4'd7; end 
                    else begin fma_req <= 1'b1; fma_op_a <= td2; fma_op_b <= x_abs; fma_op_c <= A_D0; end
                end
                
                4'd7: begin // DIV: Result = N / D
                    if (div_ack) begin
                        div_req <= 1'b0;
                        if (sign_reg) begin
                            // Nếu x âm, acos(-x) = PI - acos(|x|) -> Tính tiếp FMA
                            // Sử dụng fma_op_b là kết quả div_result nội bộ
                            state <= 4'd8; 
                        end else begin
                            out_valid <= 1'b1;
                            out_result <= div_result; // Kết quả cuối
                            status_invalid <= 1'b0;
                            state <= 4'd0;
                        end
                    end else begin
                        div_req <= 1'b1; div_op_a <= n_final; div_op_b <= d_final;
                    end
                end
                
                4'd8: begin // FMA Bù góc phần tư: Result = (-1.0 * R) + PI
                    if (fma_ack) begin
                        out_valid <= 1'b1;
                        out_result <= fma_result;
                        status_invalid <= 1'b0;
                        fma_req <= 1'b0;
                        state <= 4'd0;
                    end else begin
                        fma_req <= 1'b1;
                        fma_op_a <= NEG_ONE;
                        fma_op_b <= div_result; // Kết quả chia lấy từ ngõ vào
                        fma_op_c <= PI;
                    end
                end
                
                default: state <= 4'd0;
            endcase
        end
    end
endmodule