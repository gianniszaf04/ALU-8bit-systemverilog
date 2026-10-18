#!/usr/bin/env bash
# Compile and run all testbenches with Icarus Verilog (no make required).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
for tb in tb_alu tb_alu_edge_cases tb_alu_selfcheck; do
  echo "=== $tb"
  iverilog -g2012 -Wall -o "build/$tb.vvp" rtl/alu.sv "tb/$tb.sv"
  (cd build && vvp -n "$tb.vvp")
done
