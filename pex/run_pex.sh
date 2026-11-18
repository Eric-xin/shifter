#!/usr/bin/env bash
# Calibre xRC parasitic extraction (R + C + coupling C) of Shifter_8bit_sized,
# then splice the extracted cell into the schematic testbench netlist so
# ocean/shifter_metrics.ocn can rerun the same metrics post-layout.
#
# Run on the lab machine (Virtuoso + Calibre on PATH):
#   Shifter/pex/run_pex.sh
# Override any setting below via environment, e.g.:
#   LVS_DECK=/path/calibre.lvs PEX_DECK=/path/calibre.rcx Shifter/pex/run_pex.sh
#
# Prerequisite: one schematic run of the metrics script (or ADE) so the TB
# netlist exists in $NETLIST_DIR.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
LIB=${LIB:-Shifter}
CELL=${CELL:-Shifter_8bit_sized}
TB=${TB:-Shifter_8bit_sized_tb}
CDS_DIR=${CDS_DIR:-$HOME/Cadence}                  # dir holding cds.lib
PDK=${PDK:-/courses/ee4321/tech/tsmc65/T-N65-CM-SP-018-K3_MOM/Base_PDK/PDK_CRN65GP_v1.0c_official_IC61_20101010}
LVS_DECK=${LVS_DECK:-}       # Calibre LVS rule file; "none" if PEX_DECK already includes it
PEX_DECK=${PEX_DECK:-}       # Calibre xRC rule file (PEX statements / cap tables)
LAYERMAP=${LAYERMAP:-}       # optional strmout layer map
TECH_LIB=${TECH_LIB:-tsmcN65}               # tech library Shifter is attached to
TECH_DIR_USER=${TECH_DIR:-}                  # set to force the tech library location
TECH_DIR=${TECH_DIR:-$PDK/tsmcN65}
NETLIST_DIR=${NETLIST_DIR:-$HOME/simulation/$TB/spectre/schematic/netlist}
RUN=${RUN:-$HERE/run}
FORCE=${FORCE:-0}            # 1 = continue to PEX even if LVS is not CORRECT

say() { printf '\n=== %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

for tool in strmout si calibre python3; do
  command -v "$tool" >/dev/null || die "$tool not on PATH (load the Cadence/Calibre modules first)"
done
[ -f "$CDS_DIR/cds.lib" ] || die "no cds.lib in CDS_DIR=$CDS_DIR"

# --- locate rule decks --------------------------------------------------------
pick_deck() {  # $1 = label (LVS|PEX), rest = find predicates
  local label=$1; shift
  mapfile -t hits < <(find "$PDK" -type f "$@" 2>/dev/null | sort)
  if [ "${#hits[@]}" -eq 1 ]; then printf '%s' "${hits[0]}"; return; fi
  {
    echo "Can't pick the $label deck automatically (${#hits[@]} candidates under \$PDK)."
    printf '  %s\n' "${hits[@]:0:20}"
    echo "Set ${label}_DECK=/path/to/deck and rerun."
  } >&2
  exit 1
}
if [ -z "$LVS_DECK" ]; then
  LVS_DECK=$(pick_deck LVS -ipath '*calibre*' -ipath '*lvs*' \
             \( -iname 'calibre*.lvs' -o -iname '*lvs*.rule*' -o -iname '*.lvs' \))
fi
if [ -z "$PEX_DECK" ]; then
  PEX_DECK=$(pick_deck PEX -ipath '*calibre*' \( -ipath '*rcx*' -o -ipath '*xrc*' -o -ipath '*pex*' \) \
             \( -iname 'calibre*.rcx' -o -iname '*rcx*rule*' -o -iname '*xrc*' -o -iname '*.rcx' \))
fi
[ "$LVS_DECK" = none ] || [ -f "$LVS_DECK" ] || die "LVS_DECK not found: $LVS_DECK"
[ -f "$PEX_DECK" ] || die "PEX_DECK not found: $PEX_DECK"
echo "LVS deck: $LVS_DECK"
echo "PEX deck: $PEX_DECK"

mkdir -p "$RUN"; cd "$RUN"

# Your cds.lib only defines your own libraries; the tech library comes from your
# Virtuoso session setup (.cdsinit / course scripts). Start a headless Virtuoso
# the same way -- from $CDS_DIR -- and dump where it finds every library.
say "Resolve libraries through a headless Virtuoso session"
rm -f cds.lib
if command -v virtuoso >/dev/null && \
   (cd "$CDS_DIR" && PEX_CDSLIB_OUT="$RUN/cds.lib" PEX_LIB="$LIB" \
      timeout 600 virtuoso -nograph -replay "$HERE/dump_libs.il" -log "$RUN/virtuoso_libs.log" \
      </dev/null) > virtuoso_libs.out 2>&1 && [ -s cds.lib ]; then
  grep -h 'PEX_DUMP' virtuoso_libs.out "$RUN/virtuoso_libs.log" 2>/dev/null | head -1 \
    | sed 's/.*PEX_DUMP /Virtuoso sees: /'
else
  echo "Virtuoso library dump failed (see $RUN/virtuoso_libs.out); using TECH_DIR=$TECH_DIR"
  [ -d "$TECH_DIR" ] || die "tech library dir not found: TECH_DIR=$TECH_DIR"
  { echo "DEFINE $TECH_LIB $TECH_DIR"; echo "INCLUDE $CDS_DIR/cds.lib"; } > cds.lib
fi
[ -n "$TECH_DIR_USER" ] && echo "DEFINE $TECH_LIB $TECH_DIR_USER" >> cds.lib
echo "cds.lib for batch tools:"; sed 's/^/  /' cds.lib

lib_diag() {  # $1 = tool log
  echo "--- errors in $1"
  grep -iE 'error|fail|cannot|unable' "$1" 2>/dev/null | head -20 || true
  echo "--- last lines of $1"; tail -n 10 "$1" 2>/dev/null || true
}

# --- 1. layout -> GDS ---------------------------------------------------------
say "Stream out $LIB/$CELL/layout"
if ! (strmout -library "$LIB" -topCell "$CELL" -view layout \
        -strmFile "$RUN/$CELL.gds" -logFile "$RUN/strmout.log" \
        ${LAYERMAP:+-layerMap "$LAYERMAP"}) > strmout.out 2>&1 \
   || [ ! -s "$CELL.gds" ]; then
  cat strmout.out; lib_diag "$RUN/strmout.log"; die "strmout failed"
fi

# --- 2. schematic -> CDL (LVS source) ----------------------------------------
say "Netlist $LIB/$CELL/schematic to CDL"
cat > si.env <<EOF
simLibName = "$LIB"
simCellName = "$CELL"
simViewName = "schematic"
simSimulator = "auCdl"
simNotIncremental = 't
simReNetlistAll = 't
simViewList = '("auCdl" "schematic")
simStopList = '("auCdl")
simNetlistHier = 't
hnlNetlistFileName = "$CELL.cdl"
resistorModel = ""
shortRES = 2000.0
preserveRES = 't
checkRESVAL = 't
checkRESSIZE = 'nil
preserveCAP = 't
checkCAPVAL = 't
checkCAPAREA = 'nil
preserveDIO = 't
checkDIOAREA = 't
checkDIOPERI = 't
checkCAPPERI = 'nil
simPrintInhConnAttributes = 'nil
checkScale = "meter"
checkLDD = 'nil
pinMAP = 'nil
preserveBangInNetlist = 'nil
shrinkFACTOR = 0.0
globalPoly = 'nil
expandBusPins = 't
displayPININFO = 't
preserveALL = 't
setEQUIV = ""
incFILE = ""
auCdlDefNetlistProc = "ansCdlSubcktCall"
EOF
if ! (si "$RUN" -batch -command netlist -cdslib "$RUN/cds.lib") \
        > si.out 2>&1 || [ ! -s "$CELL.cdl" ]; then
  lib_diag "$RUN/si.out"; die "si (CDL netlist) failed"
fi

# --- 3. Calibre rules ---------------------------------------------------------
# PDK decks sometimes carry their own LAYOUT/SOURCE/report statements; comment
# those out in local copies so ours win (Calibre rejects duplicates).
strip_specs() {
  sed -E 's#^([[:space:]]*)((LAYOUT|SOURCE)[[:space:]]+(PATH|PRIMARY|SYSTEM)|LVS[[:space:]]+REPORT|MASK[[:space:]]+SVDB[[:space:]]+DIRECTORY|PEX[[:space:]]+NETLIST|PEX[[:space:]]+REPORT)#\1// \2#I' "$1"
}
{
  cat <<EOF
// Generated by run_pex.sh
LAYOUT PATH    "$RUN/$CELL.gds"
LAYOUT PRIMARY "$CELL"
LAYOUT SYSTEM  GDSII
SOURCE PATH    "$RUN/$CELL.cdl"
SOURCE PRIMARY "$CELL"
SOURCE SYSTEM  SPICE
MASK SVDB DIRECTORY "svdb" QUERY XRC
LVS REPORT "$CELL.lvs.report"
LVS REPORT OPTION NONE
LVS REPORT MAXIMUM 50
LVS POWER NAME  "VDD" "vdd!"
LVS GROUND NAME "VSS" "gnd!"
PEX NETLIST "$RUN/$CELL.pex.scs" SPECTRE SOURCENAMES
INCLUDE "$RUN/pex_deck.rules"
EOF
  [ "$LVS_DECK" = none ] || echo "INCLUDE \"$RUN/lvs_deck.rules\""
} > rules.pex
strip_specs "$PEX_DECK" > pex_deck.rules
[ "$LVS_DECK" = none ] || strip_specs "$LVS_DECK" > lvs_deck.rules
# Relative INCLUDEs inside the decks must still resolve from their PDK dirs.
sed -i -E "s#^([[:space:]]*INCLUDE[[:space:]]+\")([^/\"][^\"]*)\"#\1$(dirname "$PEX_DECK")/\2\"#I" pex_deck.rules
[ "$LVS_DECK" = none ] || \
  sed -i -E "s#^([[:space:]]*INCLUDE[[:space:]]+\")([^/\"][^\"]*)\"#\1$(dirname "$LVS_DECK")/\2\"#I" lvs_deck.rules

# --- 4. LVS -------------------------------------------------------------------
say "Calibre LVS"
calibre -lvs -hier -spice "svdb/$CELL.sp" -turbo -hyper rules.pex > lvs.log 2>&1 \
  || die "Calibre LVS failed to run, see $RUN/lvs.log"
if grep -q 'INCORRECT' "$CELL.lvs.report"; then
  echo "LVS: INCORRECT -- see $RUN/$CELL.lvs.report"
  [ "$FORCE" = 1 ] || die "fix LVS first (or FORCE=1 to extract anyway)"
elif grep -q 'CORRECT' "$CELL.lvs.report"; then
  echo "LVS: CORRECT"
else
  die "could not read LVS result from $RUN/$CELL.lvs.report"
fi

# --- 5. xRC extraction (R + C + coupling C) ----------------------------------
say "Calibre xRC (PHDB -> PDB -> FMT)"
calibre -xrc -phdb -turbo rules.pex       > xrc_phdb.log 2>&1 || die "xRC PHDB failed, see $RUN/xrc_phdb.log"
calibre -xrc -pdb -rcc -turbo rules.pex   > xrc_pdb.log  2>&1 || die "xRC PDB failed, see $RUN/xrc_pdb.log"
calibre -xrc -fmt -all rules.pex          > xrc_fmt.log  2>&1 || die "xRC FMT failed, see $RUN/xrc_fmt.log"
[ -s "$CELL.pex.scs" ] || die "no PEX netlist written, see $RUN/xrc_fmt.log"

# --- 6. splice into the TB netlist -------------------------------------------
say "Splice extracted $CELL into $TB netlist"
python3 "$HERE/splice_pex.py" --netlist-dir "$NETLIST_DIR" --cell "$CELL" \
        --pex "$RUN/$CELL.pex.scs" --out "$RUN/tb_pex.scs"

say "Done"
echo "Post-layout metrics: set in ocean/shifter_metrics.ocn"
echo "    shmPexNetlist = \"$RUN/tb_pex.scs\""
echo "and run it as before."
