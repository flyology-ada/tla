# Reporting and application command lines

`Flyology_TLA.Reporting` renders a `Replay_Result` without changing exit status. `Image` is side-effect free; `Put`
can write to stdout or to a stream explicitly supplied by the caller. `Terse` is a single-line summary; `Verbose` is
a labeled multi-line diagnostic. Control characters in failure fields are escaped so one result cannot forge extra
human-report lines. Human wording is deterministic and tested, but is not a versioned machine contract.

`JSON_Image`, `Put_JSON`, and `Write_JSON` produce the stable `flyology.tla.result/1` representation described by
`schema/result-v1.schema.json`. The older `Flyology_TLA.Replay.Write_Result` operation remains a compatibility wrapper
over the same encoder.

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
