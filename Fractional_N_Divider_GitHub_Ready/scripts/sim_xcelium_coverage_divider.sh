#!/usr/bin/env bash
# Public portfolio coverage run for the divider-only verification environment.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p sim/rtl
rm -rf cov_work

xrun -clean -sv -access +rwc -timescale 1ns/1ps \
  -coverage all -covoverwrite \
  -covtest divider_rtl \
  -top tb_frac_div_system \
  -l sim/rtl/xrun_divider_coverage.log \
  rtl/fractional_n_divider.v \
  rtl/t_flip_flop.v \
  rtl/frac_div_system.v \
  tb/tb_frac_div_system.v

grep -q "FAIL=0" sim/rtl/tb_frac_div_system.log || {
  echo "ERROR: Divider coverage run did not finish with FAIL=0"
  exit 2
}

echo "Coverage simulation passed. Open cov_work in Cadence IMC to inspect/export coverage."
