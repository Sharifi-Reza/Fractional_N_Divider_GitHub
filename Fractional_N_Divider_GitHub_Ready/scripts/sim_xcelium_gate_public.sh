#!/usr/bin/env bash
# Divider gate-level regression with maximum-delay SDF.
# Requires locally generated netlist/SDF plus a legally available technology Verilog model.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p sim/gate

: "${TECH_V:?Set TECH_V to your local technology-library Verilog model}"
NETLIST="netlist/fractional_n_divider_postsyn.v"
SDF="netlist/fractional_n_divider_postsyn.sdf"

for file in "$TECH_V" "$NETLIST" "$SDF"; do
  [[ -f "$file" ]] || { echo "ERROR: missing $file"; exit 1; }
done

xrun -clean -sv -access +rwc -timescale 1ns/1ps \
  -top tb_frac_div_system \
  +define+GATE_SIM \
  -l sim/gate/xrun_divider_gate.log \
  -v "$TECH_V" \
  "$NETLIST" \
  rtl/t_flip_flop.v \
  rtl/frac_div_system.v \
  tb/tb_frac_div_system.v

grep -q "FAIL=0" sim/gate/tb_frac_div_system_gate.log || {
  echo "ERROR: divider gate/SDF regression did not finish with FAIL=0"
  exit 2
}
echo "PASS: divider gate/SDF regression"
