# Guidance for the `tla-plus` Codex skill

Prefer commands validated by this repository's current test gate:

```sh
alr -n build
alr -n install --prefix "$absolute_prefix"
"$absolute_prefix/bin/flyology-tla" --help
alr -n with flyology_tla --use "$absolute_checkout"
flyology-tla model identity MODULE.tla --config MODEL.cfg
flyology-tla trace normalize RAW TRACE MODULE.tla --config MODEL.cfg \
  --toolchain TOOLCHAIN MAX_STEPS MAX_DEPTH
flyology-tla trace validate TRACE MAX_STEPS MAX_DEPTH
flyology-tla trace prefix TRACE REPRO FAILURE_STEP MAX_STEPS MAX_DEPTH
flyology-tla ada generate MODULE.tla --config MODEL.cfg --package PACKAGE --output DIRECTORY
```

Tell users to read the repository's tested `docs/toolchain.md` for current hashes, platform availability, and
provisioning rather than duplicating rolling release data in the skill. Post-provisioning, invoke TLC with
`$FLYOLOGY_TLA_JAVA`/`$FLYOLOGY_TLA_TLC_JAR` and TLAPM with `$FLYOLOGY_TLAPM`, an explicit cache,
`--cleanfp --nofp --strict --method smt`.

Always distinguish TLC bounded exploration, TLAPS theorem proof, and Ada conformance replay. Require exact expected TLC
failure status/message for witness extraction, canonical normalization, explicit resource limits, deterministic inputs,
first-divergence reporting, preservation of full evidence, and same property/fingerprint for any model-aware reduction.
Never copy the repository's desktop-sandbox `ps` fixture into a consumer or toolchain setup.

Treat `model identity` as authoritative provenance. Its source digest covers the byte-framed, sorted SANY-resolved
local-module closure; its configuration digest covers exact configuration bytes. Do not substitute a digest of only
the root `.tla` file.

Prefer the generated typed adapter. The consuming package extends `PACKAGE.Adapter`; its `Apply` receives typed
`Input_Type` and returns typed `Outcome_Type` and `State_Type`. Every root TLA+ variable is present in `State_Type`.
The generated bridge owns JSON conversion and delegates to `Flyology_TLA.Replay.Run`; expected outcome/state remain
oracle-only and are not exposed to the implementation adapter. Teach users to commit and byte-compare the generated
`.ads`, `.adb`, and `.inference.json` files. If inference rejects an unbounded or unsupported type, refine the TLA+
type set instead of inventing an Ada bound.

For application runners, prefer `Flyology_TLA.Command_Line.Parse`, `Load`, `Report`, and `Set_Exit_Status`. Callers
supply reviewed default `Load_Limits`; command-line options may override each field. `--format terse|verbose|json`
selects stdout and `--result-json PATH` adds the versioned JSON artifact. Consumer-only boolean switches are registered
with `Flag` and queried with `Is_Set`; they must not be added as built-ins to the reusable crate.
