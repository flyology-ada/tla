#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary_base=${TMPDIR:-/tmp}
temporary_base=${temporary_base%/}
temporary_root=$(mktemp -d "$temporary_base/flyology-tla-tests.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM

expect_failure()
{
  set +e
  "$@" >/dev/null 2>&1
  command_status=$?
  set -e
  test "$command_status" -ne 0
}

digest()
{
  if command -v sha256sum >/dev/null 2>&1
  then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

cd "$project_root"
./scripts/check-repository.sh
alr -n build
./bin/flyology-tla trace validate tests/fixtures/trace.json 10 20
./bin/flyology-tla trace normalize \
  tests/fixtures/tlc-counterexample.json "$temporary_root/normalized.json" \
  Counter Counter.cfg \
  0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
  tla2tools-1.8.0+9787e65 10 20
./bin/flyology-tla trace validate "$temporary_root/normalized.json" 10 20
cmp tests/fixtures/trace.json "$temporary_root/normalized.json"
./bin/flyology-tla trace prefix \
  tests/fixtures/trace.json "$temporary_root/prefix.json" 1 10 20
./bin/flyology-tla trace validate "$temporary_root/prefix.json" 10 20
cmp tests/fixtures/trace-prefix-1.json "$temporary_root/prefix.json"
expect_failure ./bin/flyology-tla trace validate tests/fixtures/invalid-duplicate.json 10 20
expect_failure ./bin/flyology-tla trace validate tests/fixtures/invalid-unknown-member.json 10 20
expect_failure ./bin/flyology-tla trace validate tests/fixtures/invalid-gap.json 10 20
expect_failure ./bin/flyology-tla trace validate tests/fixtures/trace.json 1 20
expect_failure ./bin/flyology-tla trace prefix tests/fixtures/trace.json \
  "$temporary_root/too-long.json" 3 10 20
expect_failure ./bin/flyology-tla trace normalize \
  tests/fixtures/invalid-tlc-gap.json "$temporary_root/invalid-normalized.json" \
  Counter Counter.cfg \
  0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
  tla2tools-1.8.0+9787e65 10 20
test ! -e "$temporary_root/invalid-normalized.json"
set +e
./bin/flyology-tla ada generate \
  tests/fixtures/Unbounded.tla \
  --config tests/fixtures/Unbounded.cfg \
  --package Invalid_Options \
  --bogus ignored >"$temporary_root/generate-options.log" 2>&1
generate_options_status=$?
set -e
test "$generate_options_status" -ne 0
grep -q 'unknown ada generate option --bogus' \
  "$temporary_root/generate-options.log"
./tests/scripts/test-toolchain.sh

cd "$project_root/tests"
alr -n build
./bin/flyology-tla-tests \
  "$project_root/tests/fixtures/trace.json" \
  "$temporary_root/result-conformant.json" \
  "$temporary_root/result-diverged.json"
cmp "$project_root/tests/fixtures/result-conformant.json" \
  "$temporary_root/result-conformant.json"
cmp "$project_root/tests/fixtures/result-diverged.json" \
  "$temporary_root/result-diverged.json"

trace_path=$project_root/tests/fixtures/trace.json
./bin/flyology-tla-command-line-probe "$trace_path" \
  >"$temporary_root/probe-terse.txt"
printf '%s\n' 'conformant: 2 modeled steps' \
  >"$temporary_root/expected-terse.txt"
cmp "$temporary_root/expected-terse.txt" "$temporary_root/probe-terse.txt"

./bin/flyology-tla-command-line-probe --format verbose "$trace_path" \
  >"$temporary_root/probe-verbose.txt"
grep -Fxq 'Verdict: conformant' "$temporary_root/probe-verbose.txt"
grep -Fxq 'Compared steps: 2' "$temporary_root/probe-verbose.txt"
grep -Fxq 'Failure step: none' "$temporary_root/probe-verbose.txt"

trace_sha256=$(digest "$trace_path")
./bin/flyology-tla-command-line-probe --format json "$trace_path" \
  >"$temporary_root/probe.json"
printf '%s\n' \
  "{\"format\":\"flyology.tla.result/1\",\"verdict\":\"conformant\",\"trace_sha256\":\"$trace_sha256\",\"compared_steps\":2,\"failure\":null}" \
  >"$temporary_root/expected-probe.json"
cmp "$temporary_root/expected-probe.json" "$temporary_root/probe.json"

./bin/flyology-tla-command-line-probe --probe \
  --result-json "$temporary_root/probe-sidecar.json" "$trace_path" \
  >"$temporary_root/probe-sidecar-human.txt"
cmp "$temporary_root/expected-terse.txt" "$temporary_root/probe-sidecar-human.txt"
cmp "$temporary_root/expected-probe.json" "$temporary_root/probe-sidecar.json"

./bin/flyology-tla-command-line-probe --help >"$temporary_root/probe-help.txt"
grep -Fq -- '--probe   exercise a consumer-defined boolean flag' \
  "$temporary_root/probe-help.txt"
expect_failure ./bin/flyology-tla-command-line-probe --probe --probe "$trace_path"
expect_failure ./bin/flyology-tla-command-line-probe --format detailed "$trace_path"
expect_failure ./bin/flyology-tla-command-line-probe --max-steps 1 "$trace_path"
expect_failure ./bin/flyology-tla-command-line-probe \
  --result-json "$trace_path" "$trace_path"
cp "$trace_path" "$temporary_root/trace-copy.json"
ln -s "$temporary_root/trace-copy.json" "$temporary_root/trace-alias.json"
expect_failure ./bin/flyology-tla-command-line-probe \
  --result-json "$temporary_root/trace-alias.json" \
  "$temporary_root/trace-copy.json"
cmp "$trace_path" "$temporary_root/trace-copy.json"

if test -n "${FLYOLOGY_TLA_JAVA:-}" \
  && test -n "${FLYOLOGY_TLA_TLC_JAR:-}" \
  && test -n "${FLYOLOGY_TLAPM:-}"
then
  "$project_root/scripts/check-formal.sh"
fi
