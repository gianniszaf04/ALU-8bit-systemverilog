// =====================================================================
//  tb_alu_edge_cases.sv - corner cases with A = 20
//    A XOR A, A AND ~A, A OR 0, A OR 1   (identities)
//    255 + 1                             (carry / overflow)
//    A / 0                               (division by zero)
//  Each case is self-checked against the expected value.
// =====================================================================
`timescale 1ns / 1ns

module tb_alu_edge_cases;
    reg  [7:0] A, B;
    reg  [3:0] ALU_Sel;
    reg        clock, reset;
    wire [7:0] ALU_Out;
    wire       CarryOut, nextcmd;

    integer errors = 0;

    alu dut (
        .A(A), .B(B), .ALU_Sel(ALU_Sel),
        .ALU_Out(ALU_Out), .CarryOut(CarryOut),
        .clock(clock), .reset(reset), .nextcmd(nextcmd)
    );

    always #5 clock = ~clock;

    // apply a command, wait for nextcmd and compare
    task run_case(input [8*12-1:0] name, input [3:0] sel, input [7:0] a, input [7:0] b,
                  input [7:0] exp_out, input exp_carry);
        begin
            @(negedge clock);
            A = a; B = b; ALU_Sel = sel;
            @(posedge nextcmd);
            if (ALU_Out === exp_out && CarryOut === exp_carry)
                $display("PASS  %-12s A=%3d B=%3d -> ALU_Out=%3d Carry=%b", name, a, b, ALU_Out, CarryOut);
            else begin
                $display("FAIL  %-12s A=%3d B=%3d -> ALU_Out=%3d Carry=%b (expected %3d / %b)",
                         name, a, b, ALU_Out, CarryOut, exp_out, exp_carry);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_alu_edge_cases.vcd");
        $dumpvars(0, tb_alu_edge_cases);

        clock = 1'b0;
        reset = 1'b0;
        #10 reset = 1'b1;
        #30 reset = 1'b0;

        run_case("A XOR A",  4'b1010, 8'd20,  8'd20,  8'd0,   1'b0);
        run_case("A AND ~A", 4'b1000, 8'd20,  ~8'd20, 8'd0,   1'b0);
        run_case("A OR 0",   4'b1001, 8'd20,  8'd0,   8'd20,  1'b0);
        // Same opcode as the previous case: only B changes. The original design
        // ignored this (it only reacted to ALU_Sel changes); the fixed one doesn't.
        run_case("A OR 1",   4'b1001, 8'd20,  8'd1,   8'd21,  1'b0);
        run_case("255 + 1",  4'b0000, 8'd255, 8'd1,   8'd0,   1'b1);
        run_case("A / 0",    4'b0011, 8'd20,  8'd0,   8'hFF,  1'b1);

        if (errors == 0) $display("ALL EDGE CASES PASSED");
        else             $display("%0d EDGE CASE(S) FAILED", errors);
        #50 $finish;
    end
endmodule
