`timescale 1ns / 1ps

// ============================================================================
// MODULE 1: FP_ATAN (Arctangent)
// Phương pháp: Đa thức Padé [2/2] -> N(x) = x*(c1 + c2*x^2), D(x) = 1 + c3*x^2
// Tính toán số chu kỳ mới (Shared Resource):
// 1 MUL (x^2) + 1 FMA (N) + 1 FMA (D) + 1 MUL (N*x) + 1 DIV (SRT) 
// = 4 + 5 + 5 + 4 + 14 = 32 chu kỳ (Cộng thêm vài clock chuyển State của FSM)
// ============================================================================
module fp_atan (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    // Giao tiếp FP_MUL
    output reg         mul_req,       
    output reg  [31:0] mul_op_a,      
    output reg  [31:0] mul_op_b,      
    input  wire        mul_ack,       
    input  wire [31:0] mul_result,    
    
    // Giao tiếp FP_FMA
    output reg         fma_req,       
    output reg  [31:0] fma_op_a,
    output reg  [31:0] fma_op_b,
    output reg  [31:0] fma_op_c,
    input  wire        fma_ack,       
    input  wire [31:0] fma_result,
    
    // Giao tiếp FP_DIV (SRT Radix-16)
    output reg         div_req,
    output reg  [31:0] div_op_a,
    output reg  [31:0] div_op_b,
    input  wire        div_ack,
    input  wire [31:0] div_result,
    
    // Đầu ra
    output reg         out_valid,
    output reg  [31:0] out_result,
    output reg         status_invalid,
    output reg         status_zero
);

    // Hằng số Padé [2/2] (Ví dụ minh họa IEEE-754)
    localparam C1 = 32'h3F800000; // 1.0
    localparam C2 = 32'h3EAAAAAB; // Tùy chỉnh hệ số tử
    localparam C3 = 32'h3F19999A; // Tùy chỉnh hệ số mẫu
    localparam ONE= 32'h3F800000; // 1.0
    
    reg [3:0] state;
    reg [31:0] x_reg;
    reg        sign_reg;
    reg [31:0] x2_reg;
    reg [31:0] n_part_reg;
    reg [31:0] d_reg;
    reg [31:0] n_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 4'd0;
            out_valid <= 1'b0;
            mul_req <= 1'b0; fma_req <= 1'b0; div_req <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            
            case (state)
                4'd0: begin
                    if (in_valid) begin
                        if (in_operand_A[30:0] == 0) begin
                            out_valid <= 1'b1;
                            out_result <= in_operand_A; // atan(0) = 0
                            status_zero <= 1'b1;
                            status_invalid <= 1'b0;
                        end else begin
                            sign_reg <= in_operand_A[31];
                            x_reg    <= {1'b0, in_operand_A[30:0]}; // Lấy trị tuyệt đối
                            state    <= 4'd1;
                        end
                    end
                end
                
                4'd1: begin // MUL: x^2
                    if (mul_ack) begin
                        x2_reg <= mul_result;
                        mul_req <= 1'b0;
                        state <= 4'd2;
                    end else begin
                        mul_req <= 1'b1; mul_op_a <= x_reg; mul_op_b <= x_reg;
                    end
                end
                
                4'd2: begin // FMA: N_part = c2 * x^2 + c1
                    if (fma_ack) begin
                        n_part_reg <= fma_result;
                        fma_req <= 1'b0;
                        state <= 4'd3;
                    end else begin
                        fma_req <= 1'b1; fma_op_a <= C2; fma_op_b <= x2_reg; fma_op_c <= C1;
                    end
                end
                
                4'd3: begin // FMA: D = c3 * x^2 + 1.0
                    if (fma_ack) begin
                        d_reg <= fma_result;
                        fma_req <= 1'b0;
                        state <= 4'd4;
                    end else begin
                        fma_req <= 1'b1; fma_op_a <= C3; fma_op_b <= x2_reg; fma_op_c <= ONE;
                    end
                end
                
                4'd4: begin // MUL: N = N_part * x
                    if (mul_ack) begin
                        n_reg <= mul_result;
                        mul_req <= 1'b0;
                        state <= 4'd5;
                    end else begin
                        mul_req <= 1'b1; mul_op_a <= n_part_reg; mul_op_b <= x_reg;
                    end
                end
                
                4'd5: begin // DIV: Result = N / D
                    if (div_ack) begin
                        out_valid <= 1'b1;
                        out_result <= {sign_reg, div_result[30:0]}; // Phục hồi dấu (hàm lẻ)
                        div_req <= 1'b0;
                        status_zero <= 1'b0;
                        status_invalid <= 1'b0;
                        state <= 4'd0;
                    end else begin
                        div_req <= 1'b1; div_op_a <= n_reg; div_op_b <= d_reg;
                    end
                end
                
                default: state <= 4'd0;
            endcase
        end
    end
endmodule