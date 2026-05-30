`timescale 1ns / 1ps

module sync_fifo_bypass #(
    parameter DATA_WIDTH = 4,
    parameter DEPTH_LOG2 = 4 // Chiều sâu 16 phần tử
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  push,
    input  wire                  pop,
    input  wire [DATA_WIDTH-1:0] data_in,
    
    output wire [DATA_WIDTH-1:0] data_out,
    output wire                  empty,
    output wire                  full
);
    reg [DATA_WIDTH-1:0] mem [0:(1<<DEPTH_LOG2)-1];
    reg [DEPTH_LOG2-1:0] wr_ptr;
    reg [DEPTH_LOG2-1:0] rd_ptr;
    reg [DEPTH_LOG2:0]   count;

    assign empty = (count == 0);
    assign full  = (count == (1<<DEPTH_LOG2));
    assign data_out = mem[rd_ptr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
        end else begin
            case ({push, pop})
                2'b10: begin
                    if (!full) begin
                        mem[wr_ptr] <= data_in;
                        wr_ptr <= wr_ptr + 1;
                        count  <= count + 1;
                    end
                end
                2'b01: begin
                    if (!empty) begin
                        rd_ptr <= rd_ptr + 1;
                        count  <= count - 1;
                    end
                end
                2'b11: begin
                    mem[wr_ptr] <= data_in;
                    wr_ptr <= wr_ptr + 1;
                    rd_ptr <= rd_ptr + 1;
                    // count giữ nguyên
                end
                default: ; // 2'b00 hoặc các trạng thái không xác định
            endcase
        end
    end
endmodule