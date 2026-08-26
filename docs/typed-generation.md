# Typed Ada package generation

`flyology-tla ada generate` uses the `tla2sany.xml.XMLExporter` contained in the pinned TLA+ Tools jar. It consumes the
resolved semantic AST rather than scraping TLA+ source text or guessing from observed JSON values. This is important:
JSON arrays do not distinguish TLA+ sets from sequences, and a bounded TLC behavior may not exercise every value.

## Model convention

The default operators are:

- `TypeOK`: a conjunction of `variable \in TypeSet` constraints covering every root-module `VARIABLE` exactly once;
- `HarnessInputType`: the set of values accepted as a materialized trace input; and
- `HarnessOutcomeType`: the set of values returned as the observable outcome.

Override their names with `--type-invariant`, `--input-type`, and `--outcome-type`. Operators must take no parameters.
The trace `state` projection must contain every generated state field at reset and after every action.

## Exact supported tier

The generator currently accepts:

- `BOOLEAN`;
- literal integer ranges such as `0..10`;
- non-empty finite string sets, emitted as prefixed Ada enumerations; and
- fixed-shape record sets whose fields recursively use supported types.

It rejects empty sets, `Nat`, `Int`, symbolic range bounds, general sets, sequences, functions/maps, unions, and any
other expression whose Ada representation or bound is not mathematically fixed. It also rejects missing or duplicate
state constraints and Ada identifier collisions after normalization. Rejection is intentional: an Ada machine integer
is not equivalent to a TLA+ natural number, and an unbounded sequence has no honest implicit Ada capacity.

## Generated boundary

The generated specification contains `State_Type`, `Input_Type`, `Outcome_Type`, an abstract typed `Adapter`, and
`Run`. `State_Type` contains every root state variable, ordered by source location. Finite string values become
prefixed enumeration literals so different fields cannot accidentally share literals.

The generated body implements a private bridge to `Flyology_TLA.Replay.Adapter`. It decodes only the modeled input,
calls the handwritten typed adapter, then encodes its observed outcome and complete post-state. It never passes expected
outcomes or expected states to the implementation side. The raw replay layer performs the same structural JSON oracle
comparison and first-divergence reporting as a manual adapter.

`flyology_json` remains imported only by `Flyology_TLA.JSON`. Generated code uses the dependency-neutral
`Flyology_TLA.Codecs` support package, keeping the future serde migration outside handwritten adapters.

## Reproducibility and review artifact

The command writes:

- `<package>.ads` and `<package>.adb`, including exact source/configuration SHA-256 comments; and
- `<package>.inference.json`, conforming to `schema/ada-inference-v1.schema.json`.

The report records the selected operators, input hashes, SANY XML hash, every state-variable mapping, inferred kind,
and evidence line. Run generation from a stable repository-relative command and byte-compare all three files in CI.

The example command is:

```sh
flyology-tla ada generate examples/counter/formal/Counter.tla \
  --config examples/counter/formal/Counter.cfg \
  --package Counter_Model \
  --output examples/counter/ada/generated
```
