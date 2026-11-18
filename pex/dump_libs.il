;; dump_libs.il -- write every library the Virtuoso session knows as a cds.lib
;; Used by run_pex.sh:  virtuoso -nograph -replay dump_libs.il
;; Env: PEX_CDSLIB_OUT = output file, PEX_LIB = design library to report on.
let((out port tf lib)
  out = getShellEnvVar("PEX_CDSLIB_OUT")
  port = outfile(out)
  fprintf(port "-- libraries as seen by a Virtuoso session (dumped by run_pex.sh)\n")
  ;; Include Cadence's built-ins (basic, analogLib) too: si does not get them
  ;; from cdsDotLibs, and auCdl needs basic/nlpglobals. Other tools may warn
  ;; that cdsDotLibs "redefines" them -- harmless.
  foreach(l ddGetLibList()
    fprintf(port "DEFINE %s %s\n" l~>name l~>readPath))
  close(port)
  lib = ddGetObj(getShellEnvVar("PEX_LIB"))
  tf = car(errset(techGetTechFile(lib)))
  printf("PEX_DUMP lib=%s path=%s tech=%s techPath=%s\n"
         getShellEnvVar("PEX_LIB") if(lib lib~>readPath "NOT FOUND")
         if(tf tf~>libName "NOT FOUND")
         if(tf && ddGetObj(tf~>libName) ddGetObj(tf~>libName)~>readPath "-")))
exit()
