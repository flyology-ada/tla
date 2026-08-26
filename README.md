# Flyology TLA+ conformance harness

This crate turns selected TLC behaviors into deterministic JSON traces and replays them through an Ada adapter. It
checks the implementation's observable outcome and semantic post-state after every modeled action. The first mismatch
is reported with a stable property/fingerprint pair and can be reproduced as a model-valid trace prefix.

The repository is deliberately below Counterweave and Flyology DB. It depends on neither; both can migrate to this
trace and replay contract as consumers. TLAPS proofs remain a separate, complementary claim: they prove TLA+ theorems,
while this harness connects bounded TLC behaviors to an implementation. Conformance replay is not a refinement proof.

## Smallest consumer surface

From an Alire crate during local adoption:

```sh
alr -n with flyology_tla --use /absolute/path/to/tla
alr -n build
```

After an indexed release, use `alr with flyology_tla` without the path pin. The recommended adapter is generated from
the model's semantic AST, so handwritten Ada never parses JSON. The lower-level `Flyology_TLA.Replay.Adapter` remains
available for dynamic or manually projected models. The complete, compiled typed example is under
`examples/counter/ada`.

The command-line tool is installable independently:

```sh
alr -n build
tool_prefix=/absolute/dedicated/prefix
alr -n install --prefix "$tool_prefix"
"$tool_prefix/bin/flyology-tla" --help
```

Alire does not add an installation prefix to `PATH`; invoke the absolute binary or add `$tool_prefix/bin` yourself.

## Provision TLA+, TLC, TLAPM, and Java

The one command installs the pinned TLA+ Tools and TLAPS distributions plus the latest Eclipse Temurin 21 GA JRE:

```sh
toolchain_root=/absolute/dedicated/cache/flyology-tla-toolchain
flyology-tla toolchain install "$toolchain_root"
flyology-tla toolchain verify "$toolchain_root"
eval "$(flyology-tla toolchain env "$toolchain_root")"
```

`install` fails closed on pinned archive digest drift. Temurin intentionally resolves latest Java 21 GA at install
time; its resolved version, archive digest, and Java-binary digest are recorded in `receipt.json`. `verify` checks the
installed files against both immutable pins and that receipt. The current TLAPS binary boundary is macOS arm64 and
Linux x86_64. Other platforms are rejected explicitly. See `docs/toolchain.md`.

## Generate a typed Ada adapter boundary

Give every state variable a finite, exact type in `TypeOK`, and describe trace inputs/outcomes as TLA+ record sets:

```tla
TypeOK == count \in 0..2 /\ lastAction \in {"Init", "Increment"}
HarnessInputType == [delta : 1..1]
HarnessOutcomeType == [accepted : BOOLEAN]
```

Then generate the package after evaluating `toolchain env`:

```sh
flyology-tla ada generate formal/tla/Model.tla \
  --config formal/tla/Model.cfg \
  --package Model_Harness \
  --output generated/tla
```

The command runs the pinned SANY XML exporter, enumerates every root-module `VARIABLE`, infers exact types, and writes
`model_harness.ads`, `model_harness.adb`, and `model_harness.inference.json`. Add `generated/tla` to the consuming GPR
project's source directories, extend `Model_Harness.Adapter`, and call `Model_Harness.Run`. The generated bridge alone
decodes/encodes trace JSON; expected outcomes and states remain oracle-only. Generation fails rather than guessing an
Ada representation for `Nat`, `Int`, unbounded collections, ambiguous names, or unsupported expressions. See
`docs/typed-generation.md`.

## Generate, normalize, and replay a behavior

A TLC witness configuration uses `ALIAS` to expose the stable action/input/outcome/state projection. TLC itself writes
the raw JSON counterexample:

```sh
"$FLYOLOGY_TLA_JAVA" -Xmx1g -XX:+UseParallelGC \
  -cp "$FLYOLOGY_TLA_TLC_JAR" tlc2.TLC \
  -workers 1 -noGenerateSpecTE -metadir "$tmp/states" \
  -config Counter.cfg -dumpTrace json "$tmp/raw.json" Counter
```

An intentional witness invariant exits with TLC status 12. Normalize only after checking that exact expected failure:

```sh
flyology-tla model identity MODULE.tla --config MODEL.cfg
flyology-tla trace normalize RAW TRACE MODULE.tla --config MODEL.cfg \
  --toolchain TOOLCHAIN_ID MAX_STEPS MAX_JSON_DEPTH
flyology-tla trace validate TRACE MAX_STEPS MAX_JSON_DEPTH
```

Replay is an Ada library operation because the implementation boundary is project-specific. The example runner shows
the complete command:

```sh
examples/counter/ada/bin/counter-conformance TRACE
```

The repository's actual end-to-end example, including strict TLAPM proof, is:

```sh
./scripts/check-formal.sh
```

It requires the four environment variables emitted by `toolchain env`.

## Contract decisions

- Trace format: new traces are canonical `flyology.tla.trace/2` JSON documents, not NDJSON. Version 2 binds the
  SANY-resolved local-module closure and exact configuration bytes; version 1 remains readable. The original TLC dump
  remains evidence.
- Model identity: `model identity` is the authoritative source/configuration hashing command. Normalization and typed
  generation call the same implementation instead of accepting consumer-computed provenance.
- In-memory envelopes: `Traces.Parse`/`Image` and `Reporting.Parse_JSON` let isolated adapters embed strict shared
  trace/result artifacts without temporary files or private codecs.
- Nondeterminism: the trace materializes every implementation-relevant choice in `input`; replay uses no randomness.
- Naming: actions and model sources are qualified `Module!Action`; optional `role` is the stable adapter dispatch role.
- Oracle: default comparison is structural JSON equality. Whitespace, object order, and equivalent string escaping do
  not matter; array order matters; JSON number token spelling is exact. Override comparison for reviewed projections.
- State boundary: compare the outcome and the semantic post-state after every transition, plus the initial state.
- Limits: callers provide all file, step, depth, name, string, and value limits. There are no library defaults.
- Reproduction: keep the full trace and result. `trace prefix` may retain the prefix through the first failure;
  arbitrary step deletion is not claimed to preserve a modeled behavior.
- Results: result/1 remains strict and supported. Explicit result/2 APIs add bounded observed outcome/state JSON for
  divergence without duplicating expected values from the exact SHA-256-bound trace.
- JSON dependency: all `flyology_json` imports are isolated in private package `Flyology_TLA.JSON` for a later serde
  migration without changing the public harness API.
- Typed adapters: SANY-derived packages expose records/enums/ranges only; JSON is confined to generated codec code and
  the dependency-neutral `Flyology_TLA.Codecs` support boundary.

The versioned schemas are under `schema`; detailed contracts are in `docs/trace-contract.md` and
`docs/adapter-contract.md`. Reusable human/JSON reporting and runner argument handling are documented in
`docs/reporting-and-cli.md`.

## Run the counter example

```sh
cd examples/counter/ada
alr -n build
./bin/counter-conformance ../traces/counter.trace.json
./bin/counter-conformance --format verbose ../traces/counter.trace.json
./bin/counter-conformance --format json ../traces/counter.trace.json
```

The example itself registers `--buggy`, which enables an intentional lost update and demonstrates the first state
divergence with a failing exit status:

```sh
./bin/counter-conformance --buggy --format verbose ../traces/counter.trace.json
```

`--result-json PATH` writes the stable JSON result alongside terse or verbose stdout. Every load-limit field can be
overridden explicitly on the command line; the example supplies its reviewed defaults.

## Tests

```sh
./scripts/test.sh
```

This builds warning-strict Ada, proves model identity changes for included-module and configuration edits,
byte-compares normalization, validates strict envelopes and prefix reproduction,
checks conformant/divergent result artifacts, exercises the toolchain installer hermetically (including tamper and
broad-root rejection), tests terse/verbose/JSON application reporting and argument failures, and builds the nested
Alire consumer. When toolchain environment variables are present it also runs the actual TLC/TLAPM gate and the
example-owned `--buggy` divergence.

Harness build, test, and provisioning commands never create or configure Git remotes.
