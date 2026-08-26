# Counter conformance example

The example combines the bounded `Counter.tla` model, its generated `Counter_Model` Ada package, and a handwritten
typed adapter. Run it from the example's Ada crate directory:

```sh
cd examples/counter/ada
alr -n build
./bin/counter-conformance ../traces/counter.trace.json
```

The default report is terse:

```text
conformant: 2 modeled steps
```

Human-readable verbose output and stable JSON are selected on the command line:

```sh
./bin/counter-conformance --format verbose ../traces/counter.trace.json
./bin/counter-conformance --format json ../traces/counter.trace.json
./bin/counter-conformance --format verbose \
  --result-json build/counter-result.json \
  ../traces/counter.trace.json
```

To see the oracle catch a real implementation defect, enable the example-owned lost-update bug:

```sh
./bin/counter-conformance --buggy --format verbose ../traces/counter.trace.json
```

It exits unsuccessfully and reports the first mismatch:

```text
Verdict: diverged
Compared steps: 1
Failure step: 1
Property: tla-conformance
Fingerprint: state:Counter!Increment
Detail: observed semantic state differs from the model after Counter!Increment
```

Use `./bin/counter-conformance --help` for limit overrides and all output options. The comments in
`ada/src/counter_conformance.adb` explain the generated boundary, honest observations, and injected demonstration bug.
