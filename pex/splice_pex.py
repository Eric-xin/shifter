#!/usr/bin/env python3
"""Swap the schematic DUT in an ADE Spectre TB netlist for a Calibre PEX netlist.

Writes:
  <out>                  TB circuit (no analyses/models; OCEAN adds those) that
                         includes the extracted cell instead of the schematic one
  <out dir>/<cell>.pex.ordered.scs
                         the PEX netlist with its subckt ports reordered to the
                         schematic order, since the TB instantiates by position
"""
import argparse
import re
import sys
from pathlib import Path

CONTROL = re.compile(
    r"^\s*(simulatorOptions|tran\b|dcOp\b|finalTimeOP\b|modelParameter\b|element\b|"
    r"outputParameter\b|designParamVals\b|primitives\b|subckts\b|saveOptions\b|save\b)")


def die(msg):
    sys.exit(f"splice_pex: {msg}")


def read_tb(netlist_dir: Path) -> str:
    """Circuit part of the ADE netlist: netlistHeader + netlist (+ footer)."""
    body = netlist_dir / "netlist"
    if body.is_file():
        parts = [netlist_dir / n for n in ("netlistHeader", "netlist", "netlistFooter")]
        return "".join(p.read_text() for p in parts if p.is_file())
    full = netlist_dir / "input.scs"
    if not full.is_file():
        die(f"no 'netlist' or 'input.scs' in {netlist_dir} -- run the schematic TB once first")
    keep = []
    for line in full.read_text().splitlines(keepends=True):
        if CONTROL.match(line):
            break  # ADE puts all control statements after the circuit
        if re.match(r'^\s*include\s+".*"\s+section\s*=', line):
            continue  # model includes: OCEAN's modelFile() adds them
        keep.append(line)
    return "".join(keep)


def header_span(lines, cell):
    """(start, end) line indices of the subckt header for cell, incl. continuations."""
    pat = re.compile(rf"^\s*\.?subckt\s+{re.escape(cell)}(\s|\(|$)", re.I)
    for i, line in enumerate(lines):
        if pat.match(line):
            j = i
            while True:
                cur = lines[j].rstrip("\n")
                nxt = lines[j + 1] if j + 1 < len(lines) else ""
                if cur.rstrip().endswith("\\") or nxt.lstrip().startswith("+"):
                    j += 1
                    continue
                return i, j
    return None


def ports_of(lines, span):
    text = " ".join(lines[span[0]:span[1] + 1])
    toks = [t.lstrip("+") for t in re.split(r"[\s()\\]+", text)]
    toks = [t for t in toks if t]
    ports = toks[2:]  # drop 'subckt' and the cell name
    return [p for p in ports if "=" not in p]  # drop any param=value


def strip_subckt(text, cell):
    """Remove the subckt definition of cell; return (new_text, schematic ports)."""
    lines = text.splitlines(keepends=True)
    span = header_span(lines, cell)
    if span is None:
        die(f"subckt {cell} not found in TB netlist")
    ports = ports_of(lines, span)
    depth, end = 0, None
    for k in range(span[0], len(lines)):
        if re.match(r"^\s*\.?subckt\b", lines[k], re.I):
            depth += 1
        elif re.match(r"^\s*\.?ends\b", lines[k], re.I):
            depth -= 1
            if depth == 0:
                end = k
                break
    if end is None:
        die(f"no 'ends' for subckt {cell}")
    out = lines[:span[0]] + [f"// {cell} schematic removed -- extracted view included below\n"] \
        + lines[end + 1:]
    return "".join(out), ports


def reorder_pex(pex_text, cell, sch_ports):
    lines = pex_text.splitlines(keepends=True)
    span = header_span(lines, cell)
    if span is None:
        die(f"subckt {cell} not found in PEX netlist")
    pex_ports = ports_of(lines, span)
    by_upper = {p.upper(): p for p in pex_ports}
    missing = [p for p in sch_ports if p.upper() not in by_upper]
    extra = sorted(set(by_upper) - {p.upper() for p in sch_ports})
    if missing or extra:
        die(f"port mismatch between schematic and PEX {cell}: "
            f"missing in PEX {missing}, extra in PEX {extra}")
    ordered = [by_upper[p.upper()] for p in sch_ports]
    spice = lines[span[0]].lstrip().startswith(".")
    head = (f".SUBCKT {cell} " + " ".join(ordered) if spice
            else f"subckt {cell} ( " + " ".join(ordered) + " )") + "\n"
    changed = ordered != pex_ports
    body = "".join(lines[:span[0]] + [head] + lines[span[1] + 1:])
    if spice:  # let Spectre read a SPICE-format extraction too
        body = "simulator lang=spice\n" + body + "\nsimulator lang=spectre\n"
    return body, changed


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--netlist-dir", required=True, type=Path)
    ap.add_argument("--cell", required=True)
    ap.add_argument("--pex", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    a = ap.parse_args()

    tb, sch_ports = strip_subckt(read_tb(a.netlist_dir), a.cell)
    pex, changed = reorder_pex(a.pex.read_text(), a.cell, sch_ports)

    ordered = a.out.parent / f"{a.cell}.pex.ordered.scs"
    ordered.write_text(pex)
    tb = "simulator lang=spectre\n" + tb
    a.out.write_text(tb.rstrip("\n") + f'\n\ninclude "{ordered.resolve()}"\n')

    print(f"schematic ports : {' '.join(sch_ports)}")
    print(f"PEX ports       : {'reordered to match' if changed else 'already in schematic order'}")
    print(f"wrote {a.out}")
    print(f"wrote {ordered}")


if __name__ == "__main__":
    main()
