#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

test -x scripts/test.sh
test -x scripts/check-formal.sh
test -x share/toolchain.sh
test -f examples/counter/ada/.gitignore
test -f examples/counter/formal/.gitignore
test -f examples/counter/ada/generated/counter_model.ads
test -f examples/counter/ada/generated/counter_model.adb
test -f examples/counter/ada/generated/counter_model.inference.json
test -f schema/ada-inference-v1.schema.json
test -f schema/model-identity-v1.schema.json
test -f schema/trace-v2.schema.json
test -f tools/flyology_tla_model_identity.ads
test -f tools/flyology_tla_model_identity.adb
test -x tests/sandbox-bin/model-identity-java
test -f src/flyology_tla-reporting.ads
test -f src/flyology_tla-command_line.ads
test -f docs/reporting-and-cli.md
test -f examples/counter/README.md

for script in scripts/*.sh tests/scripts/*.sh tests/toolchain-bin/* tests/sandbox-bin/* share/*.sh
do
  /bin/sh -n "$script"
done

imports=$(rg -l '^with Flyology_JSON[.;]' src || true)
test "$imports" = src/flyology_tla-json.adb
! rg -n 'Input_JSON|Flyology_TLA\.Codecs|Flyology_TLA\.JSON' \
  examples/counter/ada/src >/dev/null
grep -Fq 'with Flyology_TLA.Command_Line;' \
  examples/counter/ada/src/counter_conformance.adb
grep -Fq '"--buggy"' examples/counter/ada/src/counter_conformance.adb
! rg -n '^with Ada\.(Command_Line|Text_IO);' \
  examples/counter/ada/src/counter_conformance.adb >/dev/null
grep -Fq '"format":"flyology.tla.ada-inference/1"' \
  examples/counter/ada/generated/counter_model.inference.json
grep -Fq 'type State_Type is record' \
  examples/counter/ada/generated/counter_model.ads
grep -Fq 'Last_Action : State_Last_Action_Type;' \
  examples/counter/ada/generated/counter_model.ads
! rg -n -i 'with[[:space:]]+counterweave|with[[:space:]]+flyology_db' \
  src alire.toml flyology_tla.gpr >/dev/null
! rg -n '^\[\[pins\]\]' alire.toml >/dev/null

for pin in \
  https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar \
  b123b22654942bd7f8b1bcadcc47da4ee2cf4c0e \
  b123b22 \
  b658b4e504fdf0b721caf7066320f6b6fe5805f4dd2f717d0e47baba4097205e \
  ad1cb0a047ac2b5c33d6811d5d57c5bfbad4b317cd90299fee4302514f1bebde \
  bfa5e5350ac1ec7202feecad0a4a71a5bb58c16a49660448b35b6f371ba9e2f5 \
  291db0665c3b599f5343b03c06bcfb49b48ac966c39efff8643fa730f0d296b7
do
  grep -Fq "$pin" toolchain/toolchain.lock.json
  grep -Fq "$pin" share/toolchain.sh
done
! grep -Fq '/releases/assets/' toolchain/toolchain.lock.json
! grep -Fq '/releases/assets/' share/toolchain.sh

printf '%s\n' 'flyology_tla repository checks passed'
