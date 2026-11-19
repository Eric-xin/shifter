;; build_va_tb.il -- build an ADE testbench around the Verilog-A shifter_meter
;;
;; Creates schematic  Shifter/Shifter_8bit_sized_va_tb/schematic  with
;;   shifter_meter (Verilog-A) driving A0-A7/S0-S2/S0_N-S2_N, checking Y0-Y7,
;;     measuring slew/delay/power, in series with the DUT supply:
;;     VDD -> meter VDDS ... meter VDDD -> VDD_DUT -> DUT VDD
;;   Shifter_8bit_sized (VSS to ground), a 1 V vdc from VDD to ground, and an
;;   INV_150n x4 load on every output (as in the original TB).
;; Every connection is a short wire stub with a net label.
;;
;; Before loading: open shifter_meter/veriloga once in Virtuoso and save it
;; (Virtuoso parses the module and offers to create/update its symbol).
;; A missing symbol is created here as a fallback.
;;
;; Usage (CIW):  load("Shifter/ade/build_va_tb.il")
;; Then: open the TB, Launch > ADE Explorer, see ade/README.md for the setup.

shvaLib       = "Shifter"
shvaDut       = "Shifter_8bit_sized"
shvaTb        = "Shifter_8bit_sized_va_tb"
shvaVdd       = "1"            ; supply (V), must match vdd in the .va files
shvaOverwrite = nil            ; t = replace an existing TB schematic

;; ---------------------------------------------------------------- helpers
procedure(shvaPins(prefix n) let((l) for(i 0 n-1 l = cons(sprintf(nil "%s%d" prefix i) l)) reverse(l)))

procedure(shvaEnsureSymbol(cell ins outs)
  unless(ddGetObj(shvaLib cell "symbol")
    printf("Creating symbol %s/%s/symbol\n" shvaLib cell)
    schPinListToSymbol(shvaLib cell "symbol"
      list(nil 'ports
        append(mapcar(lambda((n) list(nil 'name n 'direction "input")) ins)
               mapcar(lambda((n) list(nil 'name n 'direction "output")) outs))))))

procedure(shvaPlace(cv lib cell name xy)
  let((master inst)
    master = dbOpenCellViewByType(lib cell "symbol")
    unless(master error("Cannot open %s/%s/symbol\n" lib cell))
    inst = schCreateInst(cv master name xy "R0")
    unless(inst error("Could not place %s (%s/%s)\n" name lib cell))
    inst))

;; Draw a short wire from instance pin `term` outward and label it `net`.
procedure(shvaStub(cv inst term net)
  let((tm fig box c ib dl dr dt db m p2 w)
    tm = car(setof(x inst~>master~>terminals x~>name == term))
    unless(tm error("%s has no terminal %s\n" inst~>cellName term))
    fig = car(car(tm~>pins)~>figs)
    box = dbTransformBBox(fig~>bBox inst~>transform)
    c   = centerBox(box)
    ib  = inst~>bBox
    dl = xCoord(c) - xCoord(car(ib))    dr = xCoord(cadr(ib)) - xCoord(c)
    db = yCoord(c) - yCoord(car(ib))    dt = yCoord(cadr(ib)) - yCoord(c)
    m = min(dl dr db dt)
    p2 = cond(
      (m == dl list(xCoord(c) - 0.25 yCoord(c)))
      (m == dr list(xCoord(c) + 0.25 yCoord(c)))
      (m == dt list(xCoord(c) yCoord(c) + 0.25))
      (t       list(xCoord(c) yCoord(c) - 0.25)))
    w = car(schCreateWire(cv "draw" "full" list(c p2) 0.0625 0.0625 0.0))
    schCreateWireLabel(cv w p2 net "lowerCenter" "R0" "stick" 0.0625 nil)))

procedure(shvaStubAll(cv inst nets)   ; nets: list of terminal names = net names
  foreach(n nets shvaStub(cv inst n n)))

;; ---------------------------------------------------------------- build
let((aPins sPins snPins yPins cv dut mtr vsrc gnd load yv yg yl)
  aPins  = shvaPins("A" 8)
  sPins  = shvaPins("S" 3)
  snPins = list("S0_N" "S1_N" "S2_N")
  yPins  = shvaPins("Y" 8)

  shvaEnsureSymbol("shifter_meter" append(yPins list("VDDS"))
                   append(aPins append(sPins append(snPins list("ERR" "VDDD")))))

  when(ddGetObj(shvaLib shvaTb "schematic") && !shvaOverwrite
    error("%s/%s/schematic exists -- set shvaOverwrite = t to replace it\n" shvaLib shvaTb))
  cv = dbOpenCellViewByType(shvaLib shvaTb "schematic" "schematic" "w")

  ;; (y offsets as variables: SKILL reads "list(0 -8)" as 0 minus 8)
  yv = -8.0
  yg = -11.0
  mtr  = shvaPlace(cv shvaLib "shifter_meter" "IMETER" list(0.0 0.0))
  dut  = shvaPlace(cv shvaLib shvaDut         "IDUT"   list(10.0 0.0))
  vsrc = shvaPlace(cv "analogLib" "vdc" "VSUP" list(0.0 yv))
  gnd  = shvaPlace(cv "analogLib" "gnd" "IGND" list(0.0 yg))
  dbReplaceProp(vsrc "vdc" "string" shvaVdd)

  shvaStubAll(cv mtr  append(aPins append(sPins append(snPins append(yPins list("ERR"))))))
  shvaStub(cv mtr "VDDS" "VDD")                          ; supply side of the ammeter
  shvaStub(cv mtr "VDDD" "VDD_DUT")                      ; DUT side
  shvaStubAll(cv dut  append(aPins append(sPins append(snPins append(yPins list("VSS"))))))
  shvaStub(cv dut "VDD" "VDD_DUT")
  shvaStub(cv vsrc "PLUS"  "VDD")
  shvaStub(cv vsrc "MINUS" "VSS")
  shvaStub(cv gnd  "gnd!"  "VSS")

  ;; Output loads: 4 parallel INV_150n per output (iterated instance).
  foreach(i '(0 1 2 3 4 5 6 7)
    yl = -3.0 * i
    load = shvaPlace(cv shvaLib "INV_150n" sprintf(nil "ILOAD%d<1:4>" i) list(20.0 yl))
    shvaStub(cv load "VIN"  sprintf(nil "Y%d" i))
    shvaStub(cv load "VOUT" sprintf(nil "YL%d" i))
    shvaStub(cv load "VDD"  "VDD")
    shvaStub(cv load "VSS"  "VSS"))

  schCheck(cv)
  dbSave(cv)
  printf("Built %s/%s/schematic. Open it and Launch > ADE Explorer (ade/README.md).\n"
         shvaLib shvaTb))
