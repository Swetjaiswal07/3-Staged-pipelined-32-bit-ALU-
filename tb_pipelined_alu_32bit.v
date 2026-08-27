// ============================================================
//  Module     : tb_pipelined_alu_32bit
//  Author     : Verilog Design Lab
//  Date       : June 2026
//  Tool       : Xilinx Vivado XSIM / EDA Playground (Icarus)
//
//  Self-checking testbench for pipelined_alu_32bit.
//  Pipeline latency = 3 clock cycles (3 stages).
//  Each task applies inputs, waits 3 cycles, then checks result.
//
//  HOW TO RUN
//  Vivado : Add pipelined_alu_32bit.v + this file as sim sources.
//           Set tb_pipelined_alu_32bit as top → Run Behavioral Sim.
//  EDA PG : Paste both files, top = tb_pipelined_alu_32bit, run.
// ============================================================

`timescale 1ns/1ps

module tb_pipelined_alu_32bit;

    // ─── DUT signal declarations ────────────────────────────
    reg        clk, rst_n, valid_in;
    reg [31:0] A, B;
    reg [ 3:0] opcode;

    wire [31:0] result;
    wire        zero, carry, overflow, negative, valid_out;

    // ─── DUT instantiation ──────────────────────────────────
    pipelined_alu_32bit DUT (
        .clk(clk),    .rst_n(rst_n),       .valid_in(valid_in),
        .A(A),        .B(B),               .opcode(opcode),
        .result(result),                   .zero(zero),
        .carry(carry), .overflow(overflow), .negative(negative),
        .valid_out(valid_out)
    );

    // ─── Clock : 100 MHz, 10 ns period ──────────────────────
    initial clk = 1'b1;
    always  #5 clk = ~clk;

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // ─── Task: apply inputs, wait 3 cycles, check result ────
    // Pipeline latency is exactly 3 clock cycles.
    task run_test;
        input [31:0]   a_val, b_val;
        input [ 3:0]   op;
        input [31:0]   expected;
        input [8*10:1] label;          // 10-char label for alignment
        begin
            @(posedge clk); #1;
            A = a_val;  B = b_val;  opcode = op;  valid_in = 1'b1;

            repeat (3) @(posedge clk); #1;   // flush through 3 pipeline stages

            if (result === expected) begin
                $display("  PASS | %-10s | A=%h  B=%h  =>  %h",
                          label, a_val, b_val, result);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL | %-10s | A=%h  B=%h  =>  got:%h  exp:%h",
                          label, a_val, b_val, result, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ─── Stimulus ───────────────────────────────────────────
    initial begin
        // Hold reset for 4 cycles before releasing
        rst_n = 1'b0;  valid_in = 1'b0;
        A = 32'h0;  B = 32'h0;  opcode = 4'h0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        $display("================================================");
        $display("  32-bit Pipelined ALU — Self-Checking Testbench");
        $display("  Pipeline depth : 3 stages  |  CLK : 100 MHz   ");
        $display("================================================");

        // ── Arithmetic Operations ────────────────────────────
        run_test(32'd25,        32'd10,        4'h0, 32'd35,         "ADD       ");
        run_test(32'd25,        32'd10,        4'h1, 32'd15,         "SUB       ");
        run_test(32'd6,         32'd7,         4'h2, 32'd42,         "MUL       ");
        run_test(32'd100,       32'd5,         4'h3, 32'd20,         "DIV       ");
        run_test(32'd10,        32'd0,         4'h3, 32'hDEAD_BEEF,  "DIV_ZERO  ");

        // ── Logic Operations ─────────────────────────────────
        run_test(32'hFF00FF00,  32'h0F0F0F0F,  4'h4, 32'h0F000F00,  "AND       ");
        run_test(32'hF0F0F0F0,  32'h0F0F0F0F,  4'h5, 32'hFFFFFFFF,  "OR        ");
        run_test(32'hAAAAAAAA,  32'h0,          4'h6, 32'h55555555,  "NOT       ");
        run_test(32'hFFFF0000,  32'hF0F0F0F0,  4'h7, 32'h0F0FF0F0,  "XOR       ");
        run_test(32'hFFFFFFFF,  32'hFFFFFFFF,  4'h8, 32'hFFFFFFFF,  "XNOR      ");
        run_test(32'hFFFFFFFF,  32'hFFFFFFFF,  4'h9, 32'h00000000,  "NAND      ");
        run_test(32'h00000000,  32'h00000000,  4'hA, 32'hFFFFFFFF,  "NOR       ");

        // ── Shift Operations ─────────────────────────────────
        run_test(32'h00000001,  32'd4,          4'hB, 32'h00000010,  "SHL       ");
        run_test(32'h00000001,  32'd31,         4'hB, 32'h80000000,  "SHL_31    ");
        run_test(32'h00000080,  32'd3,          4'hC, 32'h00000010,  "SHR       ");
        run_test(32'h80000000,  32'd31,         4'hC, 32'h00000001,  "SHR_31    ");

        // ── Compare Operations ───────────────────────────────
        run_test(32'd42,        32'd42,         4'hD, 32'b10,        "CMP_EQ    ");
        run_test(32'd50,        32'd10,         4'hD, 32'b01,        "CMP_GT    ");
        run_test(32'd5,         32'd10,         4'hD, 32'b00,        "CMP_LT    ");

        // ── Default (unknown opcode) ─────────────────────────
        run_test(32'hABCD1234,  32'h5678ABCD,  4'hF, 32'h00000000,  "DEFAULT   ");

        // ── Flag Checks ──────────────────────────────────────
        $display("------------------------------------------------");

        // ZERO flag : 0 + 0 = 0
        @(posedge clk); #1;
        A = 32'h0; B = 32'h0; opcode = 4'h0; valid_in = 1;
        repeat(3) @(posedge clk); #1;
        $display("  INFO | ZERO_FLAG  | zero=%b  negative=%b  (expect 1 0)", zero, negative);

        // NEGATIVE flag : 0xFFFF_FFFF - 1 = 0xFFFF_FFFE (MSB=1)
        @(posedge clk); #1;
        A = 32'hFFFFFFFF; B = 32'h1; opcode = 4'h1; valid_in = 1;
        repeat(3) @(posedge clk); #1;
        $display("  INFO | NEG_FLAG   | negative=%b  (expect 1)", negative);

        // CARRY + OVERFLOW flag : 0x7FFF_FFFF + 1 overflows signed range
        @(posedge clk); #1;
        A = 32'h7FFFFFFF; B = 32'h1; opcode = 4'h0; valid_in = 1;
        repeat(3) @(posedge clk); #1;
        $display("  INFO | OVFL_FLAG  | overflow=%b  carry=%b  (expect 1 0)", overflow, carry);

        // MUL carry : upper 32 bits non-zero
        @(posedge clk); #1;
        A = 32'hFFFFFFFF; B = 32'hFFFFFFFF; opcode = 4'h2; valid_in = 1;
        repeat(3) @(posedge clk); #1;
        $display("  INFO | MUL_CARRY  | carry=%b  (expect 1 — upper bits lost)", carry);

        // ── Summary ──────────────────────────────────────────
        $display("================================================");
        $display("  TOTAL : %0d PASS     %0d FAIL", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED — Design looks clean.");
        else
            $display("  SOME TESTS FAILED — Review the FAIL lines above.");
        $display("================================================");
        $finish;
    end

endmodule
