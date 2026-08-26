# Trace contract

The current stable format is `flyology.tla.trace/2`, described by `schema/trace-v2.schema.json`. Version 2 requires
both `model.source_sha256` and `model.configuration_sha256`. The Ada loader also reads
`flyology.tla.trace/1` for compatibility; version 1 lacks configuration-byte identity and should not be used for new
evidence. The loader independently enforces each envelope, rejects duplicate or unknown members, validates qualified
identifiers and lowercase SHA-256 values, requires contiguous step indices beginning at one, canonicalizes nested JSON
values, and applies every caller-supplied resource limit.

`Flyology_TLA.Traces.Parse` accepts an in-memory trace and can return the SHA-256 of those exact source bytes.
`Load` is the bounded file-reading wrapper over the same parser. `Image` returns a canonical full trace or modeled
prefix without a trailing line terminator; `Write_Prefix` writes that same representation plus its file line ending.
This lets process-isolated consumers embed the shared trace in their own envelopes without temporary files or a
second trace codec.

## Model and configuration identity

Use the authoritative command rather than hashing only the root module:

```sh
flyology-tla model identity MODULE.tla --config MODEL.cfg
```

It invokes the pinned SANY XML exporter and returns `flyology.tla.model-identity/1`. `configuration_sha256` hashes the
exact configuration-file bytes. `source_sha256` hashes a deterministic closure of SANY-resolved modules that exist as
ordinary `<unique-name>.tla` files beside the root module. Standard/library modules not supplied from that local model
directory do not enter the consumer-owned source closure.

Local module names are de-duplicated, bytewise sorted, and framed exactly as follows, where lengths count bytes and
`LF` is one byte:

```text
flyology.tla.model-closure/1 LF
<module-name-byte-length>:<module-name> LF
<source-byte-length>:<exact-source-bytes> LF
...
```

The framing prevents path, concatenation, and module-order ambiguity. An included local helper change alters the
source identity; a configuration-only change alters only the configuration identity. `trace normalize` and
`ada generate` use this same implementation. The identity artifact additionally records the semantic XML digest for
diagnosis, but the portable trace contract binds the source closure and configuration bytes.

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
the stable trace contract and computes model identity itself:

```sh
flyology-tla trace normalize RAW TRACE MODULE.tla --config MODEL.cfg \
  --toolchain TOOLCHAIN_ID MAX_STEPS MAX_JSON_DEPTH
```

Generation gates should regenerate and byte-compare the normalized trace.

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
