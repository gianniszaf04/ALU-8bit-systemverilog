// =====================================================================
//  tb_alu.sv - sweep of all 16 operations with A = 20, B = 3
//  Prints every result together with its measured latency.
// =====================================================================
`timescale 1ns / 1ns

module tb_alu;
    reg  [7:0] A, B;
    reg  [3:0] ALU_Sel;
    reg        clock, reset;
    wire [7:0] ALU_Out;
    wire       CarryOut, nextcmd;

    integer i;
    time    t_start;

    alu dut (
        .A(A), .B(B), .ALU_Sel(ALU_Sel),
        .ALU_Out(ALU_Out), .CarryOut(CarryOut),
        .clock(clock), .reset(reset), .nextcmd(nextcmd)
    );

    always #5 clock = ~clock;          // 100 MHz clock (10 ns period)

    function [8*5-1:0] opname(input [3:0] s);
        case (s)
            4'd0: opname = "ADD";  4'd1: opname = "SUB";  4'd2: opname = "MUL";  4'd3: opname = "DIV";
            4'd4: opname = "SHL";  4'd5: opname = "SHR";  4'd6: opname = "ROTL"; 4'd7: opname = "ROTR";
            4'd8: opname = "AND";  4'd9: opname = "OR";   4'd10: opname = "XOR"; 4'd11: opname = "NOR";
            4'd12: opname = "NAND"; 4'd13: opname = "XNOR"; 4'd14: opname = "GT"; default: opname = "EQ";
        endcase
    endfunction

    // report every completed operation
    always @(posedge nextcmd)
        $display("%8t ns | sel=%b %-4s | A=%3d B=%3d | ALU_Out=%3d (0x%h) Carry=%b | latency=%0d ns",
                 $time, ALU_Sel, opname(ALU_Sel), A, B, ALU_Out, ALU_Out, CarryOut, $time - t_start);

    initial begin
        $dumpfile("tb_alu.vcd");
        $dumpvars(0, tb_alu);

        clock = 1'b0;
        reset = 1'b0;
        #10 reset = 1'b1;              // assert reset at 10 ns
        #30 reset = 1'b0;              // release reset at 40 ns

        A = 8'd20;
        B = 8'd3;

        for (i = 0; i <= 15; i = i + 1) begin
            #5400;                     // longer than the slowest operation (ROTR, 270 cycles)
            ALU_Sel = i;
            t_start = $time;
        end
        #3000;
        $finish;
    end
endmodule
