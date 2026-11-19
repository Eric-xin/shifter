# ADE testbench with Verilog-A stimulus and checker

| Cell | View | Role |
|---|---|---|
| `shifter_stim` | veriloga | Drives `A0–A7`, `S0–S2`, `S0_N–S2_N` through all 2048 combinations, one every `period` (2 ns) |
| `shifter_check` | veriloga | Samples A, S, Y at 90 % of each period, compares Y with the expected shift, counts errors on `ERR` |
| `Shifter_8bit_sized_va_tb` | schematic | Built by `build_va_tb.il`: stim → DUT → check, VDD source, INV_150n ×4 load per output |

## One-time setup (Virtuoso)

1. `git pull` in the library so `shifter_stim/` and `shifter_check/` appear.
2. In the Library Manager, open `shifter_stim/veriloga` and `shifter_check/veriloga`,
   save each, and accept **create symbol** when asked. (This also makes the
   module parameters editable on the instances.)
3. In the CIW: `load("Shifter/ade/build_va_tb.il")`.

## ADE Explorer setup

Open `Shifter_8bit_sized_va_tb/schematic` → **Launch → ADE Explorer**.

- **Model library**: same as the existing TB —
  `.../models/spectre/crn65gplus_2d5_lk_v1d0.scs`, sections `tt` (+ `tt_bip`, `tt_dio`, `tt_dio_33` if required).
- **Analysis**: `tran`, stop = `4.2u` (≥ `tdelay + 2048·period` = 4.098 µs), errpreset = conservative.
- **Outputs** (Outputs → Add → Expression):

| Name | Expression | Pass |
|---|---|---|
| errors | `value(VT("/ERR") 4.2e-06)` | `== 0` |
| P_avg (W) | `average(IT("/IDUT/VDD") * 1.0)` | |
| P_peak (W) | `ymax(IT("/IDUT/VDD") * 1.0)` | |
| E_total (J) | `integ(IT("/IDUT/VDD") * 1.0)` | |
| Y0 rise slew | `ymax(riseTime(VT("/Y0") 0 nil 1 nil 10 90 t "cycle"))` | |
| Y0 fall slew | `ymax(fallTime(VT("/Y0") 1 nil 0 nil 10 90 t "cycle"))` | |
| tpd A0→Y0 (S=0) | `delay(?wf1 VT("/A0") ?value1 0.5 ?edge1 "either" ?nth1 1 ?wf2 VT("/Y0") ?value2 0.5 ?edge2 "either" ?nth2 1)` | |

  Save `/IDUT/VDD` (Outputs → To Be Saved → select the DUT's VDD pin) so the
  current is available. Repeat the slew rows for `Y1`–`Y7` as needed.

Run. The Spectre log (`spectre.out`) ends with

```
shifter_check: PASS  2048/2048 vectors
```

or `FAIL n of 2048` plus the first 20 failures (`A`, `S`, `Y`, expected, as
decimals); all failures go to `shifter_check.log` in the run directory.

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
