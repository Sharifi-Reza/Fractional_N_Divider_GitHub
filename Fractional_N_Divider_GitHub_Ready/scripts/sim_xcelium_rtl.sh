#!/usr/bin/env bash
# Divider RTL + external T-FF directed regression.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p sim/rtl

xrun -clean -sv -access +rwc -timescale 1ns/1ps \
  -top tb_frac_div_system \
  -l sim/rtl/xrun_divider_rtl.log \
  rtl/fractional_n_divider.v \
  rtl/t_flip_flop.v \
  rtl/frac_div_system.v \
  tb/tb_frac_div_system.v

grep -q "FAIL=0" sim/rtl/tb_frac_div_system.log || {
  echo "ERROR: divider RTL regression did not finish with FAIL=0"
  exit 2
}
echo "PASS: divider RTL regression"