# Simple Icarus Verilog flow
IVERILOG ?= iverilog
VVP      ?= vvp
GTKWAVE  ?= gtkwave
FLAGS    := -g2012 -Wall
RTL      := rtl/alu.sv
BUILD    := build

.PHONY: all sim sim-edge sim-selfcheck test wave clean

all: test

$(BUILD):
	@mkdir -p $(BUILD)

$(BUILD)/%.vvp: tb/%.sv $(RTL) | $(BUILD)
	$(IVERILOG) $(FLAGS) -o $@ $(RTL) $<

sim: $(BUILD)/tb_alu.vvp                 ## sweep all 16 ops with A=20, B=3
	cd $(BUILD) && $(VVP) -n tb_alu.vvp

sim-edge: $(BUILD)/tb_alu_edge_cases.vvp ## identities, overflow, divide by zero
	cd $(BUILD) && $(VVP) -n tb_alu_edge_cases.vvp

sim-selfcheck: $(BUILD)/tb_alu_selfcheck.vvp ## reference-model self-check
	cd $(BUILD) && $(VVP) -n tb_alu_selfcheck.vvp

test: sim-edge sim-selfcheck

wave: sim                                ## open the sweep waveform in GTKWave
	$(GTKWAVE) $(BUILD)/tb_alu.vcd &

clean:
	rm -rf $(BUILD) *.vcd *.vvp a.out
