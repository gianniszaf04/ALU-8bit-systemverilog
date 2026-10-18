# 8-bit Multi-Cycle ALU (SystemVerilog)

An 8-bit Arithmetic Logic Unit with 16 operations. A 3-state FSM controls it, and **each operation takes its own number of clock cycles**. The repo includes three testbenches, one of which checks every opcode against a reference model.

The ALU started as a university project for the course *System Design & Simulation* (Digital Systems, 2025). The course provided a buggy base design. This repo contains the fixed design plus extra verification.

## Architecture

```
            +--------------------------------------------+
 A[7:0] --->|                                            |---> ALU_Out[7:0]
 B[7:0] --->|   IDLE --(new command)--> RUN              |---> CarryOut
 ALU_Sel -->|     ^                      | (N cycles)    |---> nextcmd
 clock ---->|     +------- DONE <--------+               |
 reset ---->|                                            |
            +--------------------------------------------+
```

| State | What happens |
|-------|--------------|
| `IDLE` | Waits for a new command, meaning a change on `ALU_Sel`, `A` or `B`, or the first command after reset. It latches the opcode and operands and loads that opcode's latency. |
| `RUN`  | Counts *N* clock cycles, then writes `ALU_Out` and `CarryOut`. |
| `DONE` | Pulses `nextcmd` high for one cycle (result ready), then returns to `IDLE`. |

### Ports

| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `A`, `B` | in | 8 | Operands |
| `ALU_Sel` | in | 4 | Operation select |
| `clock` | in | 1 | Clock (testbenches use 10 ns / 100 MHz) |
| `reset` | in | 1 | Asynchronous reset, active high |
| `ALU_Out` | out | 8 | Result |
| `CarryOut` | out | 1 | Carry (ADD), borrow (SUB), overflow (MUL), divide-by-zero (DIV); 0 otherwise |
| `nextcmd` | out | 1 | One-cycle pulse when the result is ready |

### Operations

| `ALU_Sel` | Operation | `CarryOut` | Latency (cycles) |
|:---:|---|---|:---:|
| `0000` | `A + B` | carry out | 40 |
| `0001` | `A - B` | borrow (A < B) | 40 |
| `0010` | `A * B` (low 8 bits) | product > 255 | 90 |
| `0011` | `A / B` | 1 if B = 0 (result `0xFF`) | 140 |
| `0100` | `A << 1` | 0 | 10 |
| `0101` | `A >> 1` | 0 | 10 |
| `0110` | rotate A left by 1 | 0 | 190 |
| `0111` | rotate A right by 1 | 0 | 270 |
| `1000` | `A & B` | 0 | 70 |
| `1001` | `A \| B` | 0 | 70 |
| `1010` | `A ^ B` | 0 | 70 |
| `1011` | `~(A \| B)` | 0 | 70 |
| `1100` | `~(A & B)` | 0 | 110 |
| `1101` | `~(A ^ B)` | 0 | 100 |
| `1110` | `A > B ? 1 : 0` | 0 | 10 |
| `1111` | `A == B ? 1 : 0` | 0 | 10 |

`nextcmd` rises **latency + 1** cycles after the command is accepted. The slowest operation (ROTR) therefore needs about 2.7 µs, which allows at most about 370 k commands per second if every command is the slowest one. With the fastest commands (about 120 ns each) the rate is about 8 M per second.

## Fixes over the course-provided design

| # | Problem | Fix |
|---|---------|-----|
| 1 | `OR` (`1001`) computed `A & B` | `A \| B` |
| 2 | Rotate-left inserted a constant `1` instead of the MSB | `{A[6:0], A[7]}` |
| 3 | The FSM reacted **only to changes of `ALU_Sel`**, so changing just `A` or `B` never ran a new operation | It now detects changes on `ALU_Sel`, `A` and `B` |
| 4 | `prev_sel` reset to `1111`, so an `EQ` command issued right after reset was ignored | It now has an explicit "first command" flag |
| 5 | Operands were read at the **end** of `RUN`, so changing the inputs mid-operation corrupted the result | The opcode and operands are latched when the command starts |
| 6 | Division by zero produced `X` | It returns `0xFF` and sets `CarryOut = 1` |
| 7 | `CarryOut` kept a stale value after non-ADD operations | It is defined for every operation (borrow and overflow added) |

## Project structure

```
rtl/alu.sv                 ALU design
tb/tb_alu.sv               sweep of all 16 ops (A=20, B=3) with latency report
tb/tb_alu_edge_cases.sv    A^A, A&~A, A|0, A|1, 255+1 overflow, A/0
tb/tb_alu_selfcheck.sv     reference model, edge + random vectors, latency checks
Makefile, run.sh           build/run helpers
```

## Running

Requirements: [Icarus Verilog](https://github.com/steveicarus/iverilog) ≥ 11, plus [GTKWave](https://gtkwave.sourceforge.net/) for waveforms (optional).

```bash
make test          # edge cases + self-checking testbench
make sim           # 16-operation sweep
make wave          # open the sweep waveform in GTKWave
./run.sh           # run everything without make
```

To run a single testbench by hand:

```bash
iverilog -g2012 -o alu.vvp rtl/alu.sv tb/tb_alu_selfcheck.sv && vvp alu.vvp
```

**EDA Playground:** paste `rtl/alu.sv` into *design.sv* and one of the testbenches into *testbench.sv*. Then pick *Icarus Verilog 12* and tick *Open EPWave after run*.

## Sample output

The following was captured with Icarus Verilog 12.0.

`make sim`:
```
    5855 ns | sel=0000 ADD  | A= 20 B=  3 | ALU_Out= 23 (0x17) Carry=0 | latency=415 ns
   11255 ns | sel=0001 SUB  | A= 20 B=  3 | ALU_Out= 17 (0x11) Carry=0 | latency=415 ns
   17155 ns | sel=0010 MUL  | A= 20 B=  3 | ALU_Out= 60 (0x3c) Carry=0 | latency=915 ns
   23055 ns | sel=0011 DIV  | A= 20 B=  3 | ALU_Out=  6 (0x06) Carry=0 | latency=1415 ns
   27155 ns | sel=0100 SHL  | A= 20 B=  3 | ALU_Out= 40 (0x28) Carry=0 | latency=115 ns
   32555 ns | sel=0101 SHR  | A= 20 B=  3 | ALU_Out= 10 (0x0a) Carry=0 | latency=115 ns
   39755 ns | sel=0110 ROTL | A= 20 B=  3 | ALU_Out= 40 (0x28) Carry=0 | latency=1915 ns
   45955 ns | sel=0111 ROTR | A= 20 B=  3 | ALU_Out= 10 (0x0a) Carry=0 | latency=2715 ns
   49355 ns | sel=1000 AND  | A= 20 B=  3 | ALU_Out=  0 (0x00) Carry=0 | latency=715 ns
   54755 ns | sel=1001 OR   | A= 20 B=  3 | ALU_Out= 23 (0x17) Carry=0 | latency=715 ns
   60155 ns | sel=1010 XOR  | A= 20 B=  3 | ALU_Out= 23 (0x17) Carry=0 | latency=715 ns
   65555 ns | sel=1011 NOR  | A= 20 B=  3 | ALU_Out=232 (0xe8) Carry=0 | latency=715 ns
   71355 ns | sel=1100 NAND | A= 20 B=  3 | ALU_Out=255 (0xff) Carry=0 | latency=1115 ns
   76655 ns | sel=1101 XNOR | A= 20 B=  3 | ALU_Out=232 (0xe8) Carry=0 | latency=1015 ns
   81155 ns | sel=1110 GT   | A= 20 B=  3 | ALU_Out=  1 (0x01) Carry=0 | latency=115 ns
   86555 ns | sel=1111 EQ   | A= 20 B=  3 | ALU_Out=  0 (0x00) Carry=0 | latency=115 ns
```

`make test`:
```
PASS  A XOR A      A= 20 B= 20 -> ALU_Out=  0 Carry=0
PASS  A AND ~A     A= 20 B=235 -> ALU_Out=  0 Carry=0
PASS  A OR 0       A= 20 B=  0 -> ALU_Out= 20 Carry=0
PASS  A OR 1       A= 20 B=  1 -> ALU_Out= 21 Carry=0
PASS  255 + 1      A=255 B=  1 -> ALU_Out=  0 Carry=1
PASS  A / 0        A= 20 B=  0 -> ALU_Out=255 Carry=1
ALL EDGE CASES PASSED
PASS first command after reset (EQ)
PASS operands latched during RUN (200/7=28)
PASS follow-up command after change (9/2=4)
--------------------------------------------
Self-check: 451 PASS, 0 FAIL
RESULT: ALL TESTS PASSED
```

## Author

Ioannis Zafeiris
