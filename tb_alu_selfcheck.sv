// =====================================================================
//  tb_alu_selfcheck.sv - self-checking testbench
//    * every opcode with directed edge values and random operands
//    * result + CarryOut compared against a reference model
//    * latency (command -> nextcmd) checked against the opcode's delay
//    * first command after reset uses opcode 1111 (EQ)
//    * operands changed while an operation is running must not
//      corrupt the in-flight result
// =====================================================================
`timescale 1ns / 1ns

module tb_alu_selfcheck;
    reg  [7:0] A, B;
    reg  [3:0] ALU_Sel;
    reg        clock, reset;
    wire [7:0] ALU_Out;
    wire       CarryOut, nextcmd;

    integer pass_cnt = 0, fail_cnt = 0;
    integer n_random = 20;
    integer s, k, seed;
    reg [7:0] last_a, last_b;
    reg [3:0] last_sel;

    alu dut (
        .A(A), .B(B), .ALU_Sel(ALU_Sel),
        .ALU_Out(ALU_Out), .CarryOut(CarryOut),
        .clock(clock), .reset(reset), .nextcmd(nextcmd)
    );

    always #5 clock = ~clock;

    // ---------------------------------------------- reference model
    task automatic ref_model(input [3:0] sel, input [7:0] a, input [7:0] b,
                             output [7:0] r, output c);
        reg [8:0]  t9;
        reg [15:0] t16;
        begin
            c = 1'b0;
            case (sel)
                4'd0:  begin t9 = a + b;        r = t9[7:0]; c = t9[8]; end
                4'd1:  begin t9 = {1'b0,a} - {1'b0,b}; r = t9[7:0]; c = t9[8]; end
                4'd2:  begin t16 = a * b;       r = t16[7:0]; c = (t16 > 16'd255); end
                4'd3:  if (b == 0) begin r = 8'hFF; c = 1'b1; end else r = a / b;
                4'd4:  r = {a[6:0], 1'b0};
                4'd5:  r = {1'b0, a[7:1]};
                4'd6:  r = {a[6:0], a[7]};
                4'd7:  r = {a[0], a[7:1]};
                4'd8:  r = a & b;
                4'd9:  r = a | b;
                4'd10: r = a ^ b;
                4'd11: r = ~(a | b);
                4'd12: r = ~(a & b);
                4'd13: r = ~(a ^ b);
                4'd14: r = (a > b);
                default: r = (a == b);
            endcase
        end
    endtask

    function integer latency_of(input [3:0] sel);
        case (sel)
            4'd0, 4'd1:                 latency_of = 40;
            4'd2:                       latency_of = 90;
            4'd3:                       latency_of = 140;
            4'd4, 4'd5, 4'd14, 4'd15:   latency_of = 10;
            4'd6:                       latency_of = 190;
            4'd7:                       latency_of = 270;
            4'd8, 4'd9, 4'd10, 4'd11:   latency_of = 70;
            4'd12:                      latency_of = 110;
            default:                    latency_of = 100;  // XNOR
        endcase
    endfunction

    // ------------------------------------------- one checked command
    task automatic check(input [3:0] sel, input [7:0] a, input [7:0] b);
        reg [7:0] exp_r;
        reg       exp_c;
        integer   cycles, exp_cycles;
        begin
            // the ALU starts a command when its inputs change; skip exact repeats
            if (!(sel == last_sel && a == last_a && b == last_b)) begin
                ref_model(sel, a, b, exp_r, exp_c);
                exp_cycles = latency_of(sel) + 1;  // + IDLE->RUN; nextcmd rises 1 cycle after ALU_Out
                @(negedge clock);
                A = a; B = b; ALU_Sel = sel;
                cycles = 0;
                @(posedge clock); #1;              // command accepted on this edge
                while (nextcmd !== 1'b1) begin
                    @(posedge clock); #1;
                    cycles = cycles + 1;
                end
                if (ALU_Out === exp_r && CarryOut === exp_c && cycles == exp_cycles)
                    pass_cnt = pass_cnt + 1;
                else begin
                    fail_cnt = fail_cnt + 1;
                    $display("FAIL sel=%b A=%3d B=%3d : got %3d/%b in %0d cyc, expected %3d/%b in %0d cyc",
                             sel, a, b, ALU_Out, CarryOut, cycles, exp_r, exp_c, exp_cycles);
                end
                last_sel = sel; last_a = a; last_b = b;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_alu_selfcheck.vcd");
        $dumpvars(0, tb_alu_selfcheck);

        seed = 32'd2025;
        clock = 1'b0;
        reset = 1'b1;
        A = 8'd5; B = 8'd5; ALU_Sel = 4'b1111;
        last_sel = 4'bx; last_a = 8'bx; last_b = 8'bx;
        #25 reset = 1'b0;

        // 1) First command after reset is opcode 1111 with inputs already stable.
        //    (The original design initialised prev_sel to 1111 and never ran it.)
        @(posedge nextcmd); #1;
        if (ALU_Out === 8'd1) begin pass_cnt = pass_cnt + 1; $display("PASS first command after reset (EQ)"); end
        else begin fail_cnt = fail_cnt + 1; $display("FAIL first command after reset: ALU_Out=%0d", ALU_Out); end
        last_sel = 4'b1111; last_a = 8'd5; last_b = 8'd5;

        // 2) every opcode: directed edge values + random operands
        for (s = 0; s < 16; s = s + 1) begin
            check(s, 8'd0,   8'd0);
            check(s, 8'd255, 8'd255);
            check(s, 8'd255, 8'd1);
            check(s, 8'd1,   8'd255);
            check(s, 8'd128, 8'd128);
            check(s, 8'd20,  8'd3);
            check(s, 8'd129, 8'd0);
            check(s, 8'd16,  8'd16);
            for (k = 0; k < n_random; k = k + 1)
                check(s, $random(seed), $random(seed));
        end

        // 3) inputs change while DIV (140 cycles) is running
        @(negedge clock);
        A = 8'd200; B = 8'd7; ALU_Sel = 4'b0011;      // 200/7 = 28
        repeat (50) @(posedge clock);
        @(negedge clock);
        A = 8'd9;   B = 8'd2;                          // changed mid-operation
        @(posedge nextcmd); #1;
        if (ALU_Out === 8'd28) begin pass_cnt = pass_cnt + 1; $display("PASS operands latched during RUN (200/7=28)"); end
        else begin fail_cnt = fail_cnt + 1; $display("FAIL operands not latched: ALU_Out=%0d (expected 28)", ALU_Out); end
        @(posedge nextcmd); #1;                       // follow-up command 9/2 = 4
        if (ALU_Out === 8'd4) begin pass_cnt = pass_cnt + 1; $display("PASS follow-up command after change (9/2=4)"); end
        else begin fail_cnt = fail_cnt + 1; $display("FAIL follow-up: ALU_Out=%0d (expected 4)", ALU_Out); end

        $display("--------------------------------------------");
        $display("Self-check: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("RESULT: ALL TESTS PASSED");
        else               $display("RESULT: FAILURES DETECTED");
        $finish;
    end
endmodule
