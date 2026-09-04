#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
temporary_base=${TMPDIR:-/tmp}
temporary_base=${temporary_base%/}
temporary_root=$(mktemp -d "$temporary_base/flyology-tla-toolchain-test.XXXXXX")
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM

test -x "$project_root/tests/toolchain-bin/curl"
test -x "$project_root/tests/toolchain-bin/sha256sum"
test -x "$project_root/tests/toolchain-fixture/jre/bin/java"
test -x "$project_root/tests/toolchain-fixture/tlaps/bin/tlapm"

tar -czf "$temporary_root/java.tar.gz" \
  -C "$project_root/tests/toolchain-fixture" jre
tar -czf "$temporary_root/tlapm.tar.gz" \
  -C "$project_root/tests/toolchain-fixture" tlaps

export FLYOLOGY_TLA_TEST_JAR=$project_root/tests/toolchain-fixture/tla2tools.jar
export FLYOLOGY_TLA_TEST_JAVA_ARCHIVE=$temporary_root/java.tar.gz
export FLYOLOGY_TLA_TEST_TLAPM_ARCHIVE=$temporary_root/tlapm.tar.gz
PATH=$project_root/tests/toolchain-bin:$PATH
export PATH

# A release-asset replacement must fail before publishing an installation.
replacement_root="$temporary_root/replacement/toolchain"
set +e
FLYOLOGY_TLA_TEST_JAR_DIGEST=0000000000000000000000000000000000000000000000000000000000000000 \
  "$project_root/bin/flyology-tla" toolchain install "$replacement_root" \
  >/dev/null 2>&1
replacement_status=$?
set -e
test "$replacement_status" -ne 0
test ! -e "$replacement_root"

toolchain_root="$temporary_root/install root/toolchain"
"$project_root/bin/flyology-tla" toolchain install "$toolchain_root"
"$project_root/bin/flyology-tla" toolchain verify "$toolchain_root"
environment_output=$("$project_root/bin/flyology-tla" toolchain env "$toolchain_root")
printf '%s\n' "$environment_output" | grep -Fq "export FLYOLOGY_TLA_JAVA='$toolchain_root/jre/bin/java'"
printf '%s\n' "$environment_output" | grep -Fq "export FLYOLOGY_TLAPM='$toolchain_root/tlaps/bin/tlapm'"

# Replacement is allowed only after the existing install verifies.
"$project_root/bin/flyology-tla" toolchain install "$toolchain_root"

set +e
"$project_root/bin/flyology-tla" toolchain install / >/dev/null 2>&1
broad_root_status=$?
"$project_root/bin/flyology-tla" toolchain env "$temporary_root/bad'root" >/dev/null 2>&1
quoted_root_status=$?
set -e
test "$broad_root_status" -ne 0
test "$quoted_root_status" -ne 0

printf '%s\n' '# tampered' >>"$toolchain_root/jre/bin/java"
set +e
"$project_root/bin/flyology-tla" toolchain verify "$toolchain_root" >/dev/null 2>&1
tamper_status=$?
set -e
test "$tamper_status" -ne 0

printf '%s\n' 'flyology_tla hermetic toolchain installer tests passed'
