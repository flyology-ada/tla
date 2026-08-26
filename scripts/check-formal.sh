#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${FLYOLOGY_TLA_JAVA:?run 'eval \"\$(flyology-tla toolchain env)\"' first}"
: "${FLYOLOGY_TLA_TLC_JAR:?run 'eval \"\$(flyology-tla toolchain env)\"' first}"
: "${FLYOLOGY_TLAPM:?run 'eval \"\$(flyology-tla toolchain env)\"' first}"

temporary_base=${TMPDIR:-/tmp}
temporary_base=${temporary_base%/}
temporary_root=$(mktemp -d "$temporary_base/flyology-tla-formal.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM

digest()
{
  if command -v sha256sum >/dev/null 2>&1
  then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

model_root=$project_root/examples/counter/formal
test "$(digest "$FLYOLOGY_TLA_TLC_JAR")" = \
  eabd140a70f49eb9305a3bd3f3df944eddf87e5a90d329789085f8953a80533a
if test "$(uname -s):$(uname -m)" = Darwin:arm64
then
  test "$(digest "$FLYOLOGY_TLAPM")" = \
    291db0665c3b599f5343b03c06bcfb49b48ac966c39efff8643fa730f0d296b7
fi

cd "$project_root"
"$project_root/bin/flyology-tla" ada generate \
  examples/counter/formal/Counter.tla \
  --config examples/counter/formal/Counter.cfg \
  --package Counter_Model \
  --output "$temporary_root/generated-one"
"$project_root/bin/flyology-tla" ada generate \
  examples/counter/formal/Counter.tla \
  --config examples/counter/formal/Counter.cfg \
  --package Counter_Model \
  --output "$temporary_root/generated-two"
for generated_file in counter_model.ads counter_model.adb counter_model.inference.json
do
  cmp "$temporary_root/generated-one/$generated_file" \
    "$temporary_root/generated-two/$generated_file"
  cmp "$project_root/examples/counter/ada/generated/$generated_file" \
    "$temporary_root/generated-one/$generated_file"
done

set +e
"$project_root/bin/flyology-tla" ada generate \
  tests/fixtures/Unbounded.tla \
  --config tests/fixtures/Unbounded.cfg \
  --package Must_Not_Generate \
  --output "$temporary_root/unbounded" \
  >"$temporary_root/unbounded.log" 2>&1
unbounded_status=$?
set -e
test "$unbounded_status" -ne 0
grep -q "no exact Ada representation for TLA+ type operator 'Nat'" \
  "$temporary_root/unbounded.log"
test ! -e "$temporary_root/unbounded/must_not_generate.ads"

set +e
cd "$model_root"
"$FLYOLOGY_TLA_JAVA" -Xmx1g -XX:+UseParallelGC \
  -cp "$FLYOLOGY_TLA_TLC_JAR" tlc2.TLC \
  -workers 1 -coverage 1 -noGenerateSpecTE \
  -metadir "$temporary_root/tlc-states" \
  -config Counter.cfg -dumpTrace json "$temporary_root/raw.json" Counter \
  >"$temporary_root/tlc.log" 2>&1
tlc_status=$?
set -e
test "$tlc_status" -eq 12
grep -q 'Invariant WitnessPending is violated.' "$temporary_root/tlc.log"
grep -q '3 distinct states found' "$temporary_root/tlc.log"
grep -Eq '^<Increment .*: [1-9]' "$temporary_root/tlc.log"
! grep -q '^Warning:' "$temporary_root/tlc.log"

source_sha256=$(digest "$model_root/Counter.tla")
"$project_root/bin/flyology-tla" trace normalize \
  "$temporary_root/raw.json" "$temporary_root/counter.trace.json" \
  Counter Counter.cfg "$source_sha256" tla2tools-1.8.0+9787e65 10 20
"$project_root/bin/flyology-tla" trace validate \
  "$temporary_root/counter.trace.json" 10 20
cmp "$project_root/examples/counter/traces/counter.trace.json" \
  "$temporary_root/counter.trace.json"

cd "$project_root/examples/counter/ada"
alr -n build
./bin/counter-conformance "$temporary_root/counter.trace.json"
set +e
./bin/counter-conformance "$project_root/tests/fixtures/typed-invalid-input.json" \
  >"$temporary_root/typed-invalid.log" 2>&1
invalid_status=$?
set -e
test "$invalid_status" -ne 0
grep -q 'adapter:Counter!Increment' "$temporary_root/typed-invalid.log"

proof_path=$PATH
if test "${FLYOLOGY_TLA_TEST_PS_SHIM:-0}" = 1
then
  proof_path=$project_root/tests/sandbox-bin:$proof_path
fi
PATH=$proof_path "$FLYOLOGY_TLAPM" \
  --cache-dir "$temporary_root/tlapm-cache" --cleanfp --nofp \
  --strict --method smt "$model_root/CounterProof.tla" \
  >"$temporary_root/tlapm.log" 2>&1
grep -q 'All 2 obligations proved.' "$temporary_root/tlapm.log"

printf '%s\n' 'flyology_tla actual TLC trace, Ada replay, and TLAPM proof passed'
