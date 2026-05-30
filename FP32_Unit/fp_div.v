`timescale 1ns / 1ps

module fp_div #(
    parameter STAGES = 14 // Latency 14 chu ky co dinh
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [31:0] in_operand_A,
    input  wire [31:0] in_operand_B,
    
    output reg         out_valid,
    output reg  [31:0] out_result,
    output reg         status_zero,
    output reg         status_invalid
);
    localparam IDLE      = 3'd0;
    localparam ALIGN     = 3'd1;
    localparam SRT_LOOP  = 3'd2;
    localparam WAIT_PAD  = 3'd3;
    localparam NORM_PACK = 3'd4;

    reg [2:0]  state;
    reg [2:0]  loop_cnt;
    reg        sign_res;
    reg [8:0]  exp_res;
    reg [24:0] rem_a;
    reg [24:0] div_b;
    reg [25:0] quotient;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            out_valid <= 1'b0;
            out_result <= 32'd0;
            status_zero <= 1'b0;
            status_invalid <= 1'b0;
            loop_cnt <= 3'd0;
        end else begin
            out_valid <= 1'b0;
            case (state)
                IDLE: begin
                    if (in_valid) begin
                        if (~|in_operand_B[30:23]) begin 
                            out_valid <= 1'b1;
                            out_result <= {in_operand_A[31]^in_operand_B[31], 8'hFF, 23'd0}; 
                            status_invalid <= 1'b1;
                        end else if (~|in_operand_A[30:23]) begin 
                            out_valid <= 1'b1;
                            out_result <= 32'd0;
                            status_zero <= 1'b1;
                        end else begin
                            sign_res <= in_operand_A[31] ^ in_operand_B[31];
                            exp_res  <= in_operand_A[30:23] - in_operand_B[30:23] + 8'd127;
                            rem_a    <= {2'b01, in_operand_A[22:0]};
                            div_b    <= {2'b01, in_operand_B[22:0]};
                            quotient <= 26'd0;
                            loop_cnt <= 3'd6; 
                            state    <= ALIGN;
                        end
                    end
                end
                
                ALIGN: begin
                    if (rem_a >= div_b) begin
                        rem_a <= rem_a - div_b;
                        quotient[0] <= 1'b1;
                    end
                    state <= SRT_LOOP;
                end
                
                SRT_LOOP: begin
                    reg [24:0] t_rem;
                    reg [3:0]  t_q;
                    integer i;
                    
                    t_rem = rem_a;
                    t_q = 4'd0;
                    for (i = 0; i < 4; i = i + 1) begin
                        t_rem = t_rem << 1;
                        if (t_rem >= div_b) begin
                            t_rem = t_rem - div_b;
                            t_q[3-i] = 1'b1;
                        end
                    end
                    
                    rem_a <= t_rem;
                    quotient <= {quotient[21:0], t_q};
                    
                    if (loop_cnt == 3'd1) begin
                        state <= WAIT_PAD;
                        loop_cnt <= 3'd5; // Chạy đệm 5 chu kỳ để tổng độ trễ là 14
                    end else begin
                        loop_cnt <= loop_cnt - 1;
                    end
                end

                WAIT_PAD: begin
                    if (loop_cnt == 3'd1) begin
                        state <= NORM_PACK;
                    end else begin
                        loop_cnt <= loop_cnt - 1;
                    end
                end
                
                NORM_PACK: begin
                    out_valid <= 1'b1;
                    status_zero <= 1'b0;
                    status_invalid <= 1'b0;
                    
                    if (quotient[25]) begin
                        out_result <= {sign_res, exp_res[7:0], quotient[24:2]};
                    end else begin
                        out_result <= {sign_res, exp_res[7:0] - 8'd1, quotient[23:1]};
                    end
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule