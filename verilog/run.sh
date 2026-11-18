#!/usr/bin/env bash
# Run the shifter testbench against the behavioral model with Icarus Verilog.
# Extra args are passed to iverilog, e.g.:  ./run.sh -DSHIFT_LEFT   ./run.sh -DROTATE
set -euo pipefail
cd "$(dirname "$0")"
iverilog -g2005 -Wall "$@" -o tb.vvp tb_Shifter_8bit_sized.v Shifter_8bit_sized.v
vvp -n tb.vvp
