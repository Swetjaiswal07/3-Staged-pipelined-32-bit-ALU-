// ============================================================
//  Module     : pipelined_alu_32bit
//  Author     : Verilog Design Lab
//  Date       : June 2026
//  Tool       : Xilinx Vivado 2023.x  (fully synthesizable)
//  Description: 32-bit three-stage pipelined ALU with pipeline
//               registers between each stage. Supports 14 ops.
//
//  Pipeline Architecture (3 stages, 1 result/cycle at full load)
//  ┌──────────────┐   ┌──────────────┐   ┌──────────────────┐
//  │  Stage 1     │   │  Stage 2     │   │  Stage 3         │
//  │  Input Latch │──▶│  ALU Execute │──▶│  Flag + Output   │
//  │  (s1 regs)   │   │  (s2 regs)   │   │  Registration    │
//  └──────────────┘   └──────────────┘   └──────────────────┘
//  Latency = 3 clock cycles from input to valid output
//
//  OPCODE MAP  (4-bit)
//  4'h0 : ADD     A + B           4'h8 : XNOR  ~(A ^ B)
//  4'h1 : SUB     A - B           4'h9 : NAND  ~(A & B)
//  4'h2 : MUL     A * B [31:0]    4'hA : NOR   ~(A | B)
//  4'h3 : DIV     A / B *         4'hB : SHL    A << B[4:0]
//  4'h4 : AND     A & B           4'hC : SHR    A >> B[4:0]
//  4'h5 : OR      A | B           4'hD : CMP    [1]=EQ [0]=GT
//  4'h6 : NOT     ~A
//  4'h7 : XOR     A ^ B
//
//  * DIV by zero returns 32'hDEAD_BEEF, carry asserted as flag
//
//  FLAGS
//  zero     : result == 0
//  carry    : unsigned overflow / borrow / MUL upper bits
//  overflow : signed overflow (ADD / SUB only)
//  negative : result[31] (MSB indicates sign)
// ============================================================

`timescale 1ns/1ps

module pipelined_alu_32bit (
    input  wire        clk,          // System clock (rising-edge triggered)
    input  wire        rst_n,        // Active-low synchronous reset
    input  wire        valid_in,     // Asserted when A, B, opcode are stable
    input  wire [31:0] A,            // Operand A (32-bit)
    input  wire [31:0] B,            // Operand B (32-bit)
    input  wire [ 3:0] opcode,       // Operation select (see map above)
    output reg  [31:0] result,       // Computed result (valid 3 clocks after input)
    output reg         zero,         // Flag: result is zero
    output reg         carry,        // Flag: carry out / borrow / MUL overflow
    output reg         overflow,     // Flag: signed overflow (ADD/SUB)
    output reg         negative,     // Flag: MSB of result is 1
    output reg         valid_out     // Pulses high when pipeline output is valid
);

    // =========================================================
    //  STAGE 1  —  Input Registration
    //  Captures operands and opcode on the rising clock edge.
    //  Purpose: isolates combinational Stage 2 logic from any
    //  glitches or transitions on the primary inputs.
    // =========================================================
    reg [31:0] s1_A, s1_B;
    reg [ 3:0] s1_opcode;
    reg        s1_valid;

    always @(posedge clk) begin
        if (!rst_n) begin
            s1_A      <= 32'h0;
            s1_B      <= 32'h0;
            s1_opcode <= 4'h0;
            s1_valid  <= 1'b0;
        end else begin
            s1_A      <= A;
            s1_B      <= B;
            s1_opcode <= opcode;
            s1_valid  <= valid_in;
        end
    end

    // =========================================================
    //  STAGE 2  —  ALU Execution  (Combinational + Register)
    //  Intermediate wires are extended to catch carry and
    //  overflow without an explicit adder chain.
    // =========================================================

    // Extended arithmetic wires — 33-bit for ADD/SUB carry detection
    wire [32:0] add_ext = {1'b0, s1_A} + {1'b0, s1_B};
    wire [32:0] sub_ext = {1'b0, s1_A} - {1'b0, s1_B};

    // Full 64-bit product for MUL — lower 32 bits kept in result
    wire [63:0] mul_full = s1_A * s1_B;

    // Combinational ALU outputs (registered into s2 at end of Stage 2)
    reg [31:0] comb_result;
    reg        comb_carry;
    reg        comb_overflow;

    always @(*) begin
        // Safe defaults — prevents unintended latch inference
        comb_result   = 32'h0;
        comb_carry    = 1'b0;
        comb_overflow = 1'b0;

        case (s1_opcode)

            // ── Arithmetic ─────────────────────────────────────
            4'h0 : begin                         // ADD  A + B
                comb_result   = add_ext[31:0];
                comb_carry    = add_ext[32];     // unsigned carry out
                // Signed overflow: both operands same sign, result differs
                comb_overflow = (~s1_A[31] & ~s1_B[31] &  add_ext[31])
                              | ( s1_A[31] &  s1_B[31] & ~add_ext[31]);
            end

            4'h1 : begin                         // SUB  A - B
                comb_result   = sub_ext[31:0];
                comb_carry    = sub_ext[32];     // carry[32]=1 means borrow
                // Signed overflow: operands have opposite signs, result wrong
                comb_overflow = ( s1_A[31] & ~s1_B[31] & ~sub_ext[31])
                              | (~s1_A[31] &  s1_B[31] &  sub_ext[31]);
            end

            4'h2 : begin                         // MUL  A * B (lower 32 bits)
                comb_result = mul_full[31:0];
                comb_carry  = |mul_full[63:32];  // 1 if upper half is non-zero
            end

            4'h3 : begin                         // DIV  A / B (guarded)
                comb_result = (s1_B != 32'h0) ? (s1_A / s1_B) : 32'hDEAD_BEEF;
                comb_carry  = (s1_B == 32'h0);  // div-by-zero flag
            end

            // ── Bitwise Logic ──────────────────────────────────
            4'h4 : comb_result = s1_A & s1_B;          // AND
            4'h5 : comb_result = s1_A | s1_B;          // OR
            4'h6 : comb_result = ~s1_A;                 // NOT  (unary on A)
            4'h7 : comb_result = s1_A ^ s1_B;          // XOR
            4'h8 : comb_result = ~(s1_A ^ s1_B);       // XNOR
            4'h9 : comb_result = ~(s1_A & s1_B);       // NAND
            4'hA : comb_result = ~(s1_A | s1_B);       // NOR

            // ── Shift (use B[4:0] — only 5 bits needed for 32-bit shift) ──
            4'hB : comb_result = s1_A << s1_B[4:0];    // SHL  logical left
            4'hC : comb_result = s1_A >> s1_B[4:0];    // SHR  logical right

            // ── Compare  result[1]=EQ  result[0]=GT ───────────
            4'hD : comb_result = {30'b0, (s1_A == s1_B), (s1_A > s1_B)};

            // ── Unknown opcode → safe zero ─────────────────────
            default : comb_result = 32'h0;

        endcase
    end

    // Stage 2 pipeline registers
    reg [31:0] s2_result;
    reg        s2_carry;
    reg        s2_overflow;
    reg        s2_valid;

    always @(posedge clk) begin
        if (!rst_n) begin
            s2_result   <= 32'h0;
            s2_carry    <= 1'b0;
            s2_overflow <= 1'b0;
            s2_valid    <= 1'b0;
        end else begin
            s2_result   <= comb_result;
            s2_carry    <= comb_carry;
            s2_overflow <= comb_overflow;
            s2_valid    <= s1_valid;
        end
    end

    // =========================================================
    //  STAGE 3  —  Flag Computation & Output Registration
    //  All flags are derived from s2_result and registered
    //  here. This is the final pipeline stage.
    // =========================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            result    <= 32'h0;
            zero      <= 1'b0;
            carry     <= 1'b0;
            overflow  <= 1'b0;
            negative  <= 1'b0;
            valid_out <= 1'b0;
        end else begin
            result    <= s2_result;
            zero      <= (s2_result == 32'h0);
            carry     <= s2_carry;
            overflow  <= s2_overflow;
            negative  <= s2_result[31];
            valid_out <= s2_valid;
        end
    end

endmodule
