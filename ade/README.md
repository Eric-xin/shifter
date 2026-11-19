# ADE testbench with one Verilog-A block (`shifter_meter`)

`shifter_meter/veriloga` is a single Verilog-A instance that

| Job | Pins | What it does |
|---|---|---|
| **Drives** | `A0–A7`, `S0–S2`, `S0_N–S2_N` (out) | All 2048 combinations, `code = 256·S + A`, one per `period` (2 ns), edges `tr` (25 ps) |
| **Checks** | `Y0–Y7` (in), `ERR` (out) | Samples Y at 90 % of each period, compares with the expected shift; `ERR` = failing vectors (V) |
| **Measures** | `Y0–Y7`, `VDDS`/`VDDD` | 10–90 % rise/fall slew, delay (stimulus 50 % → Y at VDD/2), DUT power via a 0 V ammeter `VDDS → VDDD` |

`shifter_stim` and `shifter_check` are the earlier stand-alone pieces; they
are not needed with `shifter_meter`.

## Wiring

```
vdc (1 V): PLUS -> VDD,  MINUS -> gnd
meter VDDS -> VDD            meter VDDD -> VDD_DUT -> DUT VDD
DUT VSS    -> gnd
meter A0-A7, S0-S2, S0_N-S2_N -> DUT A0-A7, S0-S2, S0_N-S2_N
DUT Y0-Y7  -> meter Y0-Y7  (+ INV_150n x4 load per output, VDD/gnd)
meter ERR  -> net ERR (optional, for the ADE output below)
```

The DUT's VDD must reach the supply **only through the meter**; nothing else
on `VDD_DUT`. Only the meter drives A/S/S_N — no other sources on those nets.

## One-time setup (Virtuoso)

1. `git pull` in the library.
2. Open `shifter_meter/veriloga`, save it, and accept **create/update symbol**.
   If you already placed the old symbol, update the instance afterwards
   (the block gained `S0_N–S2_N` and `ERR` outputs).
3. Either wire it by hand as above, or build the TB in the CIW:
   `load("Shifter/ade/build_va_tb.il")` → `Shifter_8bit_sized_va_tb/schematic`.

## ADE Explorer setup

- **Model library**: same as the existing TB —
  `.../models/spectre/crn65gplus_2d5_lk_v1d0.scs`, section `tt` (+ `tt_bip`, `tt_dio`, `tt_dio_33` if required).
- **Analysis**: `tran`, stop = `4.2u` (≥ `tdelay + 2048·period` = 4.098 µs), errpreset = conservative.
- **Output** (optional): `errors` = `value(VT("/ERR") 4.2e-06)`, pass when `== 0`.

Run. The Spectre log (`spectre.out`) ends with

```
shifter_meter: PASS  2048/2048 vectors
shifter_meter: rise max ... ps  fall max ... ps  tpd max ... ps avg ... ps (N edges)
shifter_meter: P avg ... uW  peak ... uW  E ... pJ  -> shifter_metrics.csv
```

- `shifter_metrics.csv`: per-output rise/fall slew (max, avg), delay (max,
  avg), edge count; power avg/peak, energy, energy per edge; vectors
  checked/failed.
- `shifter_check.log`: every failing vector (`A`, `S`, `Y`, expected, decimal).

Both land in the run's `netlist/` directory; set `file` / `checkfile` to
absolute paths to put them elsewhere.

## Parameters

| Group | Parameter | Default | Meaning |
|---|---|---|---|
| stimulus | `vdd` | 1.0 | logic high / threshold reference (V) |
| | `period`, `tdelay`, `tr` | 2n, 2n, 25p | vector time, first change, edge time |
| | `nvec` | 2048 | vectors applied and checked |
| check | `tsample` | 0.9 | sample point within the period |
| | `dir` | 0 | 0: `Y[i] = A[i+S]` (toward Y0), 1: `Y[i] = A[i−S]` (toward Y7) |
| | `rotate`, `fill` | 0, 0 | rotate instead of shift; value shifted in |
| metrics | `lo`, `hi` | 0.1, 0.9 | slew thresholds (fraction of `vdd`) |
| | `ttol` | 0.1p | crossing time resolution |
| | `tstart` | 0 | ignore activity before this time |

If the check fails with a consistent pattern (e.g. every non-zero shift
wrong), the design shifts the other way or fills with 1s — set `dir` /
`fill` to match.
