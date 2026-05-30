`timescale 1ns / 1ps

module tb_cardano_top();

    reg         clk;
    reg         rst_n;
    reg         valid_in;
    reg  [7:0]  trans_id_in;
    reg  [31:0] a, b, c, d;
    
    wire        valid_out;
    wire [7:0]  trans_id_out;
    wire [1:0]  num_roots;
    wire [31:0] x1, x2, x3;
    // DÂY KẾT NỐI MỚI
    wire [31:0] x2_imag, x3_imag;
    wire [31:0] x2_mag, x3_mag;
    wire [31:0] x2_phase, x3_phase;

    cardano_top #(
        .PRE_PROCESS_STAGES(52)
    ) dut (
        .clk(clk), .rst_n(rst_n), .valid_in(valid_in),
        .trans_id_in(trans_id_in),
        .a(a), .b(b), .c(c), .d(d),
        .valid_out(valid_out), .trans_id_out(trans_id_out),
        .num_roots(num_roots), .x1(x1), .x2(x2), .x3(x3),
        .x2_imag(x2_imag), .x3_imag(x3_imag),
        .x2_mag(x2_mag), .x3_mag(x3_mag),
        .x2_phase(x2_phase), .x3_phase(x3_phase)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end

    // SCOREBOARD CHỨA 10 BÀI TEST 
    reg [31:0] t_a [1:10]; reg [31:0] t_b [1:10]; reg [31:0] t_c [1:10];  reg [31:0] t_d [1:10];
    reg [1:0]  t_nr [1:10];
    reg [31:0] t_ex1 [1:10]; reg [31:0] t_ex2 [1:10]; reg [31:0] t_ex3 [1:10];
    
    // SCOREBOARD CHO TỌA ĐỘ PHỨC
    reg [31:0] t_ex2_im [1:10]; reg [31:0] t_ex2_mag [1:10]; reg [31:0] t_ex2_ph [1:10];

    integer i;
    initial begin
        for(i = 1; i <= 10; i = i + 1) begin
            t_ex2_im[i] = 0; t_ex2_mag[i] = 0; t_ex2_ph[i] = 0;
        end

        // ID 1: Bậc 2
        t_a[1] = 32'h00000000; t_b[1] = 32'h3F800000; t_c[1] = 32'hC0A00000; t_d[1] = 32'h40C00000;
        t_nr[1] = 2; t_ex1[1] = 32'h40400000; t_ex2[1] = 32'h40000000; t_ex3[1] = 0;
        
        // ID 2: Bậc 2
        t_a[2] = 32'h00000000; t_b[2] = 32'h40000000; t_c[2] = 32'hC0800000; t_d[2] = 32'hC0C00000;
        t_nr[2] = 2; t_ex1[2] = 32'h40400000; t_ex2[2] = 32'hBF800000; t_ex3[2] = 0;

        // ID 3: Bậc 3 Lượng giác
        t_a[3] = 32'h3F800000; t_b[3] = 32'hC0C00000; t_c[3] = 32'h41300000; t_d[3] = 32'hC0C00000;
        t_nr[3] = 3; t_ex1[3] = 32'h40400000; t_ex2[3] = 32'h40000000; t_ex3[3] = 32'h3F800000;

        // ID 4: Bậc 3 Lượng giác
        t_a[4] = 32'h3F800000; t_b[4] = 32'h00000000; t_c[4] = 32'hC0E00000; t_d[4] = 32'hC0C00000;
        t_nr[4] = 3; t_ex1[4] = 32'h40400000; t_ex2[4] = 32'hBF800000; t_ex3[4] = 32'hC0000000;

        // ID 5: Bậc 3 Lượng giác (Đã sửa nghiệm)
        t_a[5] = 32'h40000000; t_b[5] = 32'hC0800000; t_c[5] = 32'hC1B00000; t_d[5] = 32'h41C00000;
        t_nr[5] = 3; t_ex1[5] = 32'h40800000; t_ex2[5] = 32'h3F800000; t_ex3[5] = 32'hC0400000;

        // ID 6: Bậc 3 Lượng giác
        t_a[6] = 32'h3F800000; t_b[6] = 32'hC0000000; t_c[6] = 32'hBF800000; t_d[6] = 32'h40000000;
        t_nr[6] = 3; t_ex1[6] = 32'h40000000; t_ex2[6] = 32'h3F800000; t_ex3[6] = 32'hBF800000;

        // ID 7: Bậc 3 Căn bậc phức (x^3 - 8 = 0)
        t_a[7] = 32'h3F800000; t_b[7] = 32'h00000000; t_c[7] = 32'h00000000; t_d[7] = 32'hC1000000;
        t_nr[7] = 1; t_ex1[7] = 32'h40000000;
        t_ex2[7]    = 32'hBF800000; // -1.0
        t_ex2_im[7] = 32'h3FDDB3D7; // ~1.732 (sqrt(3))
        t_ex2_mag[7]= 32'h40000000; // 2.0
        t_ex2_ph[7] = 32'h40060A92; // 2pi/3

        // ID 8: Bậc 3 Căn bậc phức (x^3 + 1 = 0)
        t_a[8] = 32'h3F800000; t_b[8] = 32'h00000000; t_c[8] = 32'h00000000; t_d[8] = 32'h3F800000;
        t_nr[8] = 1; t_ex1[8] = 32'hBF800000;
        t_ex2[8]    = 32'h3F000000; // 0.5
        t_ex2_im[8] = 32'h3F5DB3D7; // ~0.866 (sqrt(3)/2)
        t_ex2_mag[8]= 32'h3F800000; // 1.0
        t_ex2_ph[8] = 32'h3F860A92; // pi/3

        // ID 9: Bậc 3 Căn bậc phức (x^3 - 3x^2 + 3x - 9 = 0)
        t_a[9] = 32'h3F800000; t_b[9] = 32'hC0400000; t_c[9] = 32'h40400000; t_d[9] = 32'hC1100000;
        t_nr[9] = 1; t_ex1[9] = 32'h40400000;
        t_ex2[9]    = 32'h00000000; // 0.0
        t_ex2_im[9] = 32'h3FDDB3D7; // ~1.732 (sqrt(3))
        t_ex2_mag[9]= 32'h3FDDB3D7; // ~1.732
        t_ex2_ph[9] = 32'h3FC90FDB; // pi/2

        // ID 10: Bậc 3 Căn bậc phức (x^3 + x^2 + x - 3 = 0)
        t_a[10] = 32'h3F800000; t_b[10] = 32'h3F800000; t_c[10] = 32'h3F800000; t_d[10] = 32'hC0400000;
        t_nr[10] = 1; t_ex1[10] = 32'h3F800000;
        t_ex2[10]   = 32'hBF800000; // -1.0
        t_ex2_im[10]= 32'h3FB504F3; // ~1.414 (sqrt(2))
        t_ex2_mag[10]= 32'h3FDDB3D7; // ~1.732 (sqrt(3))
        t_ex2_ph[10]= 32'h400BE8FB; // ~2.186
    end

    function match_float;
        input [31:0] f1; input [31:0] f2;
        reg [31:0] diff;
        begin
            if (f1[31] != f2[31] && f1[30:0] != 0 && f2[30:0] != 0) match_float = 0;
            else begin
                diff = (f1[30:0] > f2[30:0]) ? (f1[30:0] - f2[30:0]) : (f2[30:0] - f1[30:0]);
                match_float = (diff < 32'd25000);
            end
        end
    endfunction

    integer push_idx;
    integer pop_cnt = 0;
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // LUỒNG PUSH
    initial begin
        valid_in = 0; trans_id_in = 0; a = 0; b = 0; c = 0; d = 0;
        rst_n = 0;
        repeat(5) @(posedge clk); rst_n = 1; repeat(5) @(posedge clk);

        $display("\n=======================================================");
        $display("   BAT DAU BOM PIPELINE BACK-TO-BACK (ID TAGGING)      ");
        $display("=======================================================\n");
        for(push_idx = 1; push_idx <= 10; push_idx = push_idx + 1) begin
            a = t_a[push_idx]; b = t_b[push_idx]; c = t_c[push_idx]; d = t_d[push_idx];
            trans_id_in = push_idx; // Gắn ID từ 1 đến 10
            valid_in = 1;
            @(posedge clk);
        end
        valid_in = 0;
    end

    // LUỒNG POP OUT-OF-ORDER
    reg is_pass;
    always @(posedge clk) begin
        if (valid_out) begin
            $display("[TIME: %0t ns] POP OUT-OF-ORDER -> TRAN_ID = %0d", $time, trans_id_out);
            $display("-> Expected Roots: %0d | X1: %h | X2: %h | X3: %h", t_nr[trans_id_out], t_ex1[trans_id_out], t_ex2[trans_id_out], t_ex3[trans_id_out]);
            $display("-> Hardware Roots: %0d | X1: %h | X2: %h | X3: %h", num_roots, x1, x2, x3);
            
            is_pass = 0;
            if (num_roots == t_nr[trans_id_out]) begin
                if (num_roots == 1) begin
                    $display("-> Complex Info  : Imag=%h | Mag=%h | Phase=%h", x2_imag, x2_mag, x2_phase);
                    // KIỂM TRA ĐỒNG THỜI NGHIỆM THỰC VÀ BỘ TOẠ ĐỘ PHỨC
                    is_pass = match_float(x1, t_ex1[trans_id_out]) &&
                              match_float(x2, t_ex2[trans_id_out]) &&
                              match_float(x2_imag, t_ex2_im[trans_id_out]) &&
                              match_float(x2_mag, t_ex2_mag[trans_id_out]) &&
                              match_float(x2_phase, t_ex2_ph[trans_id_out]);
                end else if (num_roots == 2) begin
                    is_pass = (match_float(x1, t_ex1[trans_id_out]) && match_float(x2, t_ex2[trans_id_out])) ||
                              (match_float(x1, t_ex2[trans_id_out]) && match_float(x2, t_ex1[trans_id_out]));
                end else if (num_roots == 3) begin
                    is_pass = (match_float(x1, t_ex1[trans_id_out]) && match_float(x2, t_ex2[trans_id_out]) && match_float(x3, t_ex3[trans_id_out])) ||
                              (match_float(x1, t_ex1[trans_id_out]) && match_float(x2, t_ex3[trans_id_out]) && match_float(x3, t_ex2[trans_id_out])) ||
                              (match_float(x1, t_ex2[trans_id_out]) && match_float(x2, t_ex1[trans_id_out]) && match_float(x3, t_ex3[trans_id_out])) ||
                              (match_float(x1, t_ex2[trans_id_out]) && match_float(x2, t_ex3[trans_id_out]) && match_float(x3, t_ex1[trans_id_out])) ||
                              (match_float(x1, t_ex3[trans_id_out]) && match_float(x2, t_ex1[trans_id_out]) && match_float(x3, t_ex2[trans_id_out])) ||
                              (match_float(x1, t_ex3[trans_id_out]) && match_float(x2, t_ex2[trans_id_out]) && match_float(x3, t_ex1[trans_id_out]));
                end
            end

            if (is_pass) begin $display("=> RESULT: [PASS]\n");
                pass_cnt = pass_cnt + 1; end 
            else         begin $display("=> RESULT: [FAIL]\n");
                fail_cnt = fail_cnt + 1; end

            pop_cnt = pop_cnt + 1;
            if (pop_cnt == 10) begin
                $display("=======================================================");
                $display(" TONG KET: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
                $display("=======================================================\n");
                $finish;
            end
        end
    end

endmodule