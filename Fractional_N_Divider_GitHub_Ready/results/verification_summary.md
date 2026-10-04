# Verification Results Summary

## Direct divider + external T-FF regression

The same self-checking testbench was exercised at RTL and with the synthesized divider
using maximum-delay SDF back-annotation.

| Configuration | Result | Long-term frequency test |
|---|---:|---:|
| RTL | 13 PASS / 0 FAIL | 62.445011 kHz measured vs 62.415238 kHz theoretical (0.047701% error) |
| Gate + maximum SDF | 13 PASS / 0 FAIL | 62.445011 kHz measured vs 62.415238 kHz theoretical (0.047701% error) |

The direct regression covers asynchronous reset, N=1/2/3 modes, N=2 duty cycle,
N=3 1-high/2-low waveform behavior, dynamic N=2->N=3 and N=2->N=1 transitions,
invalid-command fallback, long-term average frequency, and the external T-FF output.
Continuous monitors detect runt/glitch pulses and missing output clocks.

## SDM -> divider -> T-FF integration regression

Ten input/dither scenarios were exercised:

- Zero
- +0.25
- -0.25
- Exact +50 ppm
- Exact -50 ppm
- Zero with dither
- +0.25 with dither
- -0.25 with dither
- +50 ppm with dither
- -50 ppm with dither

Each configuration completed 52 checks with zero failures:

| SDM | Divider | Result |
|---|---|---:|
| RTL | RTL | 52 PASS / 0 FAIL |
| Post-synthesis | RTL | 52 PASS / 0 FAIL |
| RTL | Post-synthesis | 52 PASS / 0 FAIL |
| Post-synthesis | Post-synthesis | 52 PASS / 0 FAIL |

Checks include reset-state behavior, valid divider commands, generated/applied average N,
measured output-frequency agreement, T-FF divide-by-two behavior, period-boundary ratio
updates, and runt-pulse monitoring.

## Coverage note

The project contains Xcelium coverage runs using `-coverage all`. The final archive does
not include the exported numerical IMC coverage report for the final Week-4 implementation,
so this public summary intentionally does not claim a numerical coverage percentage.
