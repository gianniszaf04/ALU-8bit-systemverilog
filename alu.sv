// =====================================================================
//  alu.sv - 8-bit multi-cycle ALU with operation-dependent latency
// ---------------------------------------------------------------------
//  A 3-state FSM (IDLE -> RUN -> DONE) controls execution:
//    IDLE : waits until a new command is presented (ALU_Sel, A or B
//           changed, or first command after reset). Operands and opcode
//           are latched and the latency for that opcode is loaded.
//    RUN  : counts <latency> clock cycles, then writes the result to
//           ALU_Out / CarryOut.
//    DONE : raises nextcmd for one clock cycle (result ready) and
//           returns to IDLE.
//
//  Opcodes (ALU_Sel)                         latency (cycles)
//    0000  A + B         CarryOut = carry          40
//    0001  A - B         CarryOut = borrow         40
//    0010  A * B         CarryOut = overflow       90
//    0011  A / B         B==0 -> 0xFF, CarryOut=1 140
//    0100  A << 1                                  10
//    0101  A >> 1                                  10
//    0110  rotate A left by 1                     190
//    0111  rotate A right by 1                    270
//    1000  A & B                                   70
//    1001  A | B                                   70
//    1010  A ^ B                                   70
//    1011  ~(A | B)                                70
//    1100  ~(A & B)                               110
//    1101  ~(A ^ B)                               100
//    1110  (A > B)  ? 1 : 0                        10
//    1111  (A == B) ? 1 : 0                        10
// =====================================================================
`timescale 1ns / 1ns

module alu (
    input  wire [7:0] A, B,        // 8-bit operands
    input  wire [3:0] ALU_Sel,     // operation select
    output reg  [7:0] ALU_Out,     // 8-bit result
    output reg        CarryOut,    // carry / borrow / overflow / div-by-zero flag
    input  wire       clock,
    input  wire       reset,       // asynchronous, active high
    output reg        nextcmd      // 1-cycle pulse: result ready, ALU free
);
    // ------------------------------------------------------------ FSM
    localparam [1:0] IDLE = 2'b00,
                     RUN  = 2'b01,
                     DONE = 2'b10;

    reg [1:0]  state;
    reg [15:0] counter;
    reg [15:0] delay_cycles;

    // Latched command (operands are captured when the command starts,
    // so changing the inputs during RUN cannot corrupt the result).
    reg [3:0]  op_sel;
    reg [7:0]  op_a, op_b;
    reg        first_cmd;          // forces execution of the first command after reset

    // ------------------------------------------------- latency (cycles)
    parameter ADD_DELAY   = 40;
    parameter SUB_DELAY   = 40;
    parameter MUL_DELAY   = 90;
    parameter DIV_DELAY   = 140;
    parameter LOGIC_DELAY = 10;    // used by GT / EQ
    parameter SHL_DELAY   = 10;
    parameter SHR_DELAY   = 10;
    parameter ROTL_DELAY  = 190;
    parameter ROTR_DELAY  = 270;
    parameter AND_DELAY   = 70;
    parameter OR_DELAY    = 70;
    parameter XOR_DELAY   = 70;
    parameter NOR_DELAY   = 70;
    parameter NAND_DELAY  = 110;
    parameter XNOR_DELAY  = 100;

    // ------------------------------------------- arithmetic helpers
    wire [8:0]  sum  = {1'b0, op_a} + {1'b0, op_b};
    wire [8:0]  diff = {1'b0, op_a} - {1'b0, op_b};
    wire [15:0] prod = op_a * op_b;

    // ignore undriven (X/Z) inputs, e.g. before the testbench sets ALU_Sel
    wire inputs_known = (^{ALU_Sel, A, B} !== 1'bx);
    wire new_cmd = first_cmd || (ALU_Sel != op_sel) || (A != op_a) || (B != op_b);

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state        <= IDLE;
            counter      <= 16'd0;
            delay_cycles <= 16'd0;
            ALU_Out      <= 8'd0;
            CarryOut     <= 1'b0;
            nextcmd      <= 1'b0;
            op_sel       <= 4'd0;
            op_a         <= 8'd0;
            op_b         <= 8'd0;
            first_cmd    <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    nextcmd <= 1'b0;
                    counter <= 16'd0;

                    // Start a new command only when the inputs are valid (no X/Z)
                    if (inputs_known && new_cmd) begin
                        first_cmd <= 1'b0;
                        op_sel    <= ALU_Sel;
                        op_a      <= A;
                        op_b      <= B;

                        case (ALU_Sel)
                            4'b0000: delay_cycles <= ADD_DELAY;
                            4'b0001: delay_cycles <= SUB_DELAY;
                            4'b0010: delay_cycles <= MUL_DELAY;
                            4'b0011: delay_cycles <= DIV_DELAY;
                            4'b0100: delay_cycles <= SHL_DELAY;
                            4'b0101: delay_cycles <= SHR_DELAY;
                            4'b0110: delay_cycles <= ROTL_DELAY;
                            4'b0111: delay_cycles <= ROTR_DELAY;
                            4'b1000: delay_cycles <= AND_DELAY;
                            4'b1001: delay_cycles <= OR_DELAY;
                            4'b1010: delay_cycles <= XOR_DELAY;
                            4'b1011: delay_cycles <= NOR_DELAY;
                            4'b1100: delay_cycles <= NAND_DELAY;
                            4'b1101: delay_cycles <= XNOR_DELAY;
                            default: delay_cycles <= LOGIC_DELAY;   // GT, EQ
                        endcase
                        state <= RUN;
                    end
                end

                RUN: begin
                    if (counter < delay_cycles - 1)
                        counter <= counter + 1'b1;
                    else begin
                        CarryOut <= 1'b0;                 // default: no flag
                        case (op_sel)
                            4'b0000: begin ALU_Out <= sum[7:0];  CarryOut <= sum[8];  end // ADD
                            4'b0001: begin ALU_Out <= diff[7:0]; CarryOut <= diff[8]; end // SUB (borrow)
                            4'b0010: begin ALU_Out <= prod[7:0]; CarryOut <= |prod[15:8]; end // MUL
                            4'b0011: begin                                            // DIV
                                if (op_b == 8'd0) begin
                                    ALU_Out  <= 8'hFF;            // defined result for /0
                                    CarryOut <= 1'b1;             // error flag
                                end else
                                    ALU_Out  <= op_a / op_b;
                            end
                            4'b0100: ALU_Out <= op_a << 1;                     // SHL
                            4'b0101: ALU_Out <= op_a >> 1;                     // SHR
                            4'b0110: ALU_Out <= {op_a[6:0], op_a[7]};          // ROTL
                            4'b0111: ALU_Out <= {op_a[0],   op_a[7:1]};        // ROTR
                            4'b1000: ALU_Out <= op_a & op_b;                   // AND
                            4'b1001: ALU_Out <= op_a | op_b;                   // OR
                            4'b1010: ALU_Out <= op_a ^ op_b;                   // XOR
                            4'b1011: ALU_Out <= ~(op_a | op_b);                // NOR
                            4'b1100: ALU_Out <= ~(op_a & op_b);                // NAND
                            4'b1101: ALU_Out <= ~(op_a ^ op_b);                // XNOR
                            4'b1110: ALU_Out <= (op_a >  op_b) ? 8'd1 : 8'd0;  // GT
                            4'b1111: ALU_Out <= (op_a == op_b) ? 8'd1 : 8'd0;  // EQ
                            default: ALU_Out <= 8'd0;
                        endcase
                        state <= DONE;
                    end
                end

                DONE: begin
                    nextcmd <= 1'b1;   // result ready
                    state   <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
