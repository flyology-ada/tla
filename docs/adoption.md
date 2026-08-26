# Adoption checklist

1. Add the library with `alr with flyology_tla` (or `--use ABSOLUTE_CHECKOUT` while developing).
2. Install the `flyology-tla` executable into a dedicated Alire prefix if the consuming repository does not build it
   transitively as a tool crate.
3. Provision and verify the isolated TLA+/TLAPS/Temurin toolchain; evaluate `toolchain env` only after verification.
4. Keep TLA+ modules/configurations and the reviewed `ALIAS` projection under `formal/tla` in the consumer.
5. Run TLC single-worker with an explicit heap, metadir, configuration, module, and `-dumpTrace json` path.
6. Check TLC's exact expected exit and invariant/property message before normalizing a witness.
7. Run `model identity`, then normalize with the module/configuration paths; validate, regenerate, and byte-compare
   committed `flyology.tla.trace/2` traces. Do not supply a root-file-only digest.
8. Define finite `TypeOK`, `HarnessInputType`, and `HarnessOutcomeType` operators, then run
   `flyology-tla ada generate MODULE.tla --config MODEL.cfg --package PACKAGE --output DIRECTORY`.
9. Add the generated directory to the consuming GPR `Source_Dirs`, extend the generated `PACKAGE.Adapter`, and use
   `PACKAGE.Run` with explicit load/replay limits. Handwritten adapter code should contain no JSON.
10. Use `Flyology_TLA.Command_Line` for the trace path, caller-owned limit defaults/overrides, output selection, exact
    trace hashing, JSON sidecars, and exit status. Register only boolean application-specific flags through it.
11. Use `Flyology_TLA.Reporting` directly when an application needs human or JSON rendering without command-line I/O.
12. Regenerate and byte-compare the generated `.ads`, `.adb`, and `.inference.json` files in CI.
13. Store full traces and version-dispatched result artifacts. Use `flyology.tla.result/2` when post-adapter reporting
    must retain the observed outcome/state at divergence; result/1 remains supported. Reproduce with a prefix ending
    at the first failure.
14. Run TLAPM separately with an explicit cache and strict method; do not represent conformance replay as proof.

Counterweave and Flyology DB should consume this lower contract rather than being dependencies of it. A migration may
translate existing recorded choices/workloads into `flyology.tla.trace/2`, but the old artifact alone is not evidence
that Ada replay occurred.
