# ADE testbench with Verilog-A stimulus, checker and metrics meter

| Cell | View | Role |
|---|---|---|
| `shifter_stim` | veriloga | Drives `A0–A7`, `S0–S2`, `S0_N–S2_N` through all 2048 combinations, one every `period` (2 ns) |
| `shifter_check` | veriloga | Samples A, S, Y at 90 % of each period, compares Y with the expected shift, counts errors on `ERR` |
| `shifter_meter` | veriloga | Measures slew (10–90 %), delay (last A/S edge → Y at VDD/2) and supply power in-simulation; writes `shifter_metrics.csv` |
| `Shifter_8bit_sized_va_tb` | schematic | Built by `build_va_tb.il`: stim → DUT → check, meter in the DUT supply, VDD source, INV_150n ×4 load per output |

## One-time setup (Virtuoso)

1. `git pull` in the library so `shifter_stim/`, `shifter_check/` and `shifter_meter/` appear.
2. In the Library Manager, open `shifter_stim/veriloga`, `shifter_check/veriloga` and `shifter_meter/veriloga`,
   save each, and accept **create symbol** when asked. (This also makes the
   module parameters editable on the instances.)
3. In the CIW: `load("Shifter/ade/build_va_tb.il")`.

## ADE Explorer setup

Open `Shifter_8bit_sized_va_tb/schematic` → **Launch → ADE Explorer**.

- **Model library**: same as the existing TB —
  `.../models/spectre/crn65gplus_2d5_lk_v1d0.scs`, sections `tt` (+ `tt_bip`, `tt_dio`, `tt_dio_33` if required).
- **Analysis**: `tran`, stop = `4.2u` (≥ `tdelay + 2048·period` = 4.098 µs), errpreset = conservative.
- **Output** (Outputs → Add → Expression): `errors` = `value(VT("/ERR") 4.2e-06)`, pass when `== 0`.

Run. The Spectre log (`spectre.out`) ends with

```
shifter_check: PASS  2048/2048 vectors
shifter_meter: rise max ... ps  fall max ... ps  tpd max ... ps avg ... ps (N edges)
shifter_meter: P avg ... uW  peak ... uW  E ... pJ  -> shifter_metrics.csv
```

- **Function**: `FAIL n of 2048` plus the first 20 failures (`A`, `S`, `Y`,
  expected, as decimals) if wrong; all failures go to `shifter_check.log`.
- **Metrics**: `shifter_metrics.csv` — per-output rise/fall slew (max, avg),
  delay (max, avg), edge count, and power avg/peak, energy, energy per edge —
  same layout as the earlier metrics CSV. Both files are written to the run's
  `netlist/` directory (set the meter's `file` parameter to an absolute path
  to put the CSV elsewhere).

Meter parameters: `vdd` (threshold reference), `lo`/`hi` (slew thresholds,
default 0.1/0.9), `tstart` (ignore activity before this time), `ttol`
(crossing time resolution, default 0.1 ps).

## If the checker disagrees with the design

The expected function defaults to a logical shift toward `Y0` with zero fill
(`Y[i] = A[i+S]`). If the failures show a consistent pattern, set the
`shifter_check` instance parameters (or the defaults in its `veriloga.va`):

| Parameter | 0 | 1 |
|---|---|---|
| `dir` | toward Y0 (`Y[i] = A[i+S]`) | toward Y7 (`Y[i] = A[i−S]`) |
| `rotate` | shift | rotate |
| `fill` | shift in 0 | shift in 1 |

Changing `period` or `tdelay` on the stimulus requires the same values on the
checker (and a longer stop time).
