# Trace contract

The stable format is `flyology.tla.trace/1`, described by `schema/trace-v1.schema.json`. The Ada loader independently
enforces the envelope, rejects duplicate or unknown members, validates qualified identifiers and lowercase source
SHA-256, requires contiguous step indices beginning at one, canonicalizes nested JSON values, and applies every
caller-supplied resource limit.

## TLC alias projection

TLC's raw JSON must contain `counterexample.state`, whose entries are `[ordinal, alias]`. The initial alias supplies
`state`. Every later alias supplies:

- `action`: TLA+ action name, qualified by the normalizer if needed;
- `role`: optional stable adapter dispatch role;
- `input`: all materialized choices needed to execute the transition;
- `outcome`: expected observable result;
- `state`: expected semantic post-state; and
- `model_source`: the reviewed model action/projection source, qualified if needed.

Raw TLC JSON is provenance, not a public compatibility format. `trace normalize` is the only supported projection to
the stable trace contract. Generation gates should regenerate and byte-compare the normalized trace.

## Nondeterminism

TLC may explore a nondeterministic model, but a materialized trace is deterministic. Any choice that affects adapter
behavior belongs in `input`; ambient randomness, clocks, process identifiers, and unordered iteration must be either
modeled and materialized or removed from the adapter's semantic projection.

## Reproduction and reduction

The replay result records the first divergence/property fingerprint. Preserve the complete original trace and its
SHA-256. This repository supports only prefix reproduction:

```sh
flyology-tla trace prefix FULL_TRACE REPRO_TRACE FAILURE_STEP MAX_STEPS MAX_JSON_DEPTH
```

A prefix of a behavior remains a modeled behavior. Deleting or reordering interior actions generally does not. More
powerful shrinking belongs in a model-aware consumer; it must replay candidates and retain the same property and stable
fingerprint.
