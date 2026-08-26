# Reporting and application command lines

`Flyology_TLA.Reporting` renders a `Replay_Result` without changing exit status. `Image` is side-effect free; `Put`
can write to stdout or to a stream explicitly supplied by the caller. `Terse` is a single-line summary; `Verbose` is
a labeled multi-line diagnostic. Control characters in failure fields are escaped so one result cannot forge extra
human-report lines. Human wording is deterministic and tested, but is not a versioned machine contract.

The original overloads of `JSON_Image`, `Put_JSON`, and `Write_JSON` produce the stable
`flyology.tla.result/1` representation described by `schema/result-v1.schema.json`. They remain unchanged for current
consumers. `Parse_JSON` accepts only result/1; it does not silently widen to later versions.

The overloads taking `Replay_Result_V2` explicitly produce `flyology.tla.result/2`, described by
`schema/result-v2.schema.json`. `Parse_JSON_V2` accepts only that format and exposes its structured comparison.
Both strict decoders return the referenced trace SHA-256 separately for binding to the exact canonical trace, reject
duplicate, unknown, and missing members, and apply the caller's trace limits. Embedded observed JSON values are
canonicalized, with value and string limits enforced independently for outcome and state. All schema verdicts,
including `invalid-trace`, are represented by `Flyology_TLA.Replay.Verdict`.

Result/2 keeps verdict, property, fingerprint, and detail as the authoritative failure classification. Only a
`diverged` result has `failure.observed`. A positive failure step carries the adapter's raw JSON `outcome` and `state`;
step zero represents the initial-state comparison with `outcome: null` and the observed state. Expected values are not
duplicated: step zero references `initial.state`, while a positive step references that trace step's `expected`
object. `adapter-error` deliberately discards attempted observations because no trustworthy semantic comparison
completed; `invalid-trace` is likewise observation-free. A literal observed JSON `null` remains distinct from an
absent observation in the Ada API.

`Replay_Result` itself is unchanged so existing full record aggregates remain source compatible. The v2 API uses a
`Replay_Result_V2` containing the original summary and a private, discriminated `Observed_Comparison`.
`Replay.Run` is overloaded to fill either result version. `With_Initial_Observation` and `With_Step_Observation` allow
bounded construction when a caller already has a summary and raw observed JSON. The older
`Flyology_TLA.Replay.Write_Result` operation remains a compatibility wrapper, with a v2 overload for explicit use.

## Reusable runner arguments

`Flyology_TLA.Command_Line.Parse` implements this application-facing grammar:

```text
PROGRAM [OPTIONS] TRACE

  --format terse|verbose|json
  --result-json PATH
  --max-file-bytes N
  --max-steps N
  --max-json-depth N
  --max-object-names N
  --max-name-bytes N
  --max-string-bytes N
  --max-value-bytes N
  --help
```

The default output format is terse. `--result-json` writes a JSON artifact in addition to the selected stdout format;
it is rejected if it resolves to the trace path. Limit options override the `Load_Limits` supplied by the consuming
application. The library supplies no universal resource defaults.

`Command_Line.Report` is overloaded by result type: passing `Replay_Result` emits result/1, while passing
`Replay_Result_V2` emits result/2. There is no verdict-driven automatic upgrade, so conformant and nonconformant
artifacts from an existing result/1 migration remain result/1.

`Load` parses the trace and retains the SHA-256 of those exact bytes in the private configuration. `Report` uses that
load-time identity for JSON stdout and sidecars, so a later file change cannot silently relabel a replay result.
`Set_Exit_Status` selects success only for `Conformant`.

## Consumer-defined flags

An application can register boolean long options without adding them to the reusable crate:

```ada
Flags : Flyology_TLA.Command_Line.Application_Flag_Array :=
  [1 => Flyology_TLA.Command_Line.Flag
    ("--buggy", "run with an intentional demonstration bug")];

Config := Flyology_TLA.Command_Line.Parse (Default_Limits, Flags);
Buggy := Flyology_TLA.Command_Line.Is_Set (Flags (1));
```

Registered flags must use lowercase `--long-option` names, cannot collide with built-in options, take no value, and
are rejected when repeated. Applications that require valued domain-specific options should parse those separately
rather than weakening unknown-option validation.
