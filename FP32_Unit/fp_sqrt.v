`timescale 1ns / 1ps

module pade_sqrt_rom (
    input  wire        clk,
    input  wire [7:0]  addr,
    output reg  [31:0] data_out
);
    // Ep trinh tong hop (Vivado) dung Block RAM
    (* rom_style = "block" *) reg [31:0] rom_array [0:255];

    initial begin
        // File mem nay chua 256 ma Hex cua so Float32 (VD: 3F800000)
        $readmemh("pade_sqrt_fp32.mem", rom_array);
    end

    always @(posedge clk) begin
        data_out <= rom_array[addr];
    end
endmodule

`timescale 1ns / 1ps

module fp_sqrt #(
    parameter STAGES = 18
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    
    // --- GIAO TIEP VOI BO NHAN (FP_MUL) ---
    output reg         mul_req,       
    output reg  [31:0] mul_op_a,      
    output reg  [31:0] mul_op_b,      
    input  wire        mul_ack,       
    input  wire [31:0] mul_result,    
    
    // --- GIAO TIEP VOI BO FMA (FP_FMA) ---
    output reg         fma_req,       
    output reg  [31:0] fma_op_a,
    output reg  [31:0] fma_op_b,
    output reg  [31:0] fma_op_c,
    input  wire        fma_ack,       
    input  wire [31:0] fma_result,
    
    // --- GIAO DIEN DAU RA ---
    output reg         out_valid,
    output reg  [31:0] out_result,
    output reg         status_invalid,
    output reg         status_zero,
    output reg         status_overflow,
    output reg         status_underflow
);

    reg [4:0]  state;
    reg [31:0] y0_fp, w_fp, t1_fp, y1_fp;
    reg [7:0]  k_exp;
    
    wire [7:0]  lut_addr = w_fp[22:15];
    wire [31:0] lut_data_fp; 
    
    pade_sqrt_rom u_rom (
        .clk(clk), 
        .addr(lut_addr), 
        .data_out(lut_data_fp)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 5'd0;
            out_valid <= 1'b0;
            mul_req <= 1'b0;
            fma_req <= 1'b0;
            status_overflow <= 1'b0;
            status_underflow <= 1'b0;
        end else begin
            out_valid <= 1'b0;
            mul_req   <= 1'b0; 
            fma_req   <= 1'b0;
            
            case (state)
                0: begin 
                    if (in_valid) begin
                        if (in_operand_A[31] && in_operand_A[30:0] != 0) begin 
                            out_valid <= 1'b1;
                            out_result <= {1'b1, 8'hFF, 23'd1}; // NaN
                            status_invalid <= 1'b1;
                        end else if (in_operand_A[30:0] == 0) begin 
                            out_valid <= 1'b1;
                            out_result <= 32'd0;
                            status_zero <= 1'b1;
                        end else begin
                            begin : PRE_PROCESS_SQRT
                                wire signed [8:0] e_diff = $signed({1'b0, in_operand_A[30:23]}) - 9'sd127;
                                k_exp <= e_diff >>> 1; // Dich phai co dau de chia 2
                                
                                if (e_diff[0] == 1'b1) begin
                                    w_fp <= {1'b0, 8'd128, in_operand_A[22:0]}; // So mu le -> w * 2.0
                                end else begin
                                    w_fp <= {1'b0, 8'd127, in_operand_A[22:0]}; // So mu chan -> w * 1.0
                                end
                            end
                            state <= 5'd1;
                        end
                    end
                end
                
                1: state <= 5'd2; // Cho ROM
                
                2: begin
                    y0_fp <= lut_data_fp;
                    state <= 5'd3;
                end
                
                // NR Step 1: t1 = y0 * y0
                3: begin
                    mul_req  <= 1'b1;
                    mul_op_a <= y0_fp;
                    mul_op_b <= y0_fp;
                    state    <= 5'd4;
                end
                4: if (mul_ack) begin
                    t1_fp <= mul_result;
                    state <= 5'd5;
                end
                
                // NR Step 2: FMA -> t2 = 1.5 - 0.5 * w * t1
                5: begin
                    fma_req  <= 1'b1;
                    fma_op_a <= {~w_fp[31], w_fp[30:23] - 8'd1, w_fp[22:0]}; // -0.5 * w
                    fma_op_b <= t1_fp;
                    fma_op_c <= 32'h3FC00000; // 1.5 (Float32)
                    state    <= 5'd6;
                end
                6: if (fma_ack) begin
                    mul_req  <= 1'b1;
                    mul_op_a <= y0_fp;
                    mul_op_b <= fma_result; // t2
                    state    <= 5'd7;
                end
                
                // NR Step 3: y1 = y0 * t2
                7: if (mul_ack) begin
                    y1_fp <= mul_result;
                    mul_req  <= 1'b1;
                    mul_op_a <= w_fp;
                    mul_op_b <= mul_result;
                    state    <= 5'd8;
                end
                
                // Final Step: sqrt(w) = w * y1
                8: if (mul_ack) begin
                    out_valid  <= 1'b1;
                    out_result <= {1'b0, mul_result[30:23] + k_exp, mul_result[22:0]};
                    status_invalid <= 1'b0;
                    status_zero <= 1'b0;
                    state      <= 5'd0;
                end
                
                default: state <= 5'd0;
            endcase
        end
    end
endmodule