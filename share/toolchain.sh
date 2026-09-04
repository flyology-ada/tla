#!/bin/sh
set -eu

TLA_TOOLS_URL=https://api.github.com/repos/tlaplus/tlaplus/releases/assets/543242582
TLA_TOOLS_SHA256=16b8cd970e07147ff91f126baecba7edd98202e5ab33220a42f8f4358ee94b2b
TLAPM_DARWIN_URL=https://github.com/tlaplus/tlapm/releases/download/1.6.0-pre/tlapm-1.6.0-pre-arm64-darwin.tar.gz
TLAPM_DARWIN_SHA256=ad1cb0a047ac2b5c33d6811d5d57c5bfbad4b317cd90299fee4302514f1bebde
TLAPM_DARWIN_BINARY_SHA256=291db0665c3b599f5343b03c06bcfb49b48ac966c39efff8643fa730f0d296b7
TLAPM_LINUX_URL=https://github.com/tlaplus/tlapm/releases/download/1.6.0-pre/tlapm-1.6.0-pre-x86_64-linux-gnu.tar.gz
TLAPM_LINUX_SHA256=bfa5e5350ac1ec7202feecad0a4a71a5bb58c16a49660448b35b6f371ba9e2f5
TEMURIN_URL_BASE=https://api.adoptium.net/v3/binary/latest/21/ga

die()
{
  printf '%s\n' "flyology-tla: $*" >&2
  exit 1
}

default_root()
{
  if test -n "${FLYOLOGY_TLA_TOOLCHAIN:-}"
  then
    printf '%s\n' "$FLYOLOGY_TLA_TOOLCHAIN"
  elif test -n "${XDG_CACHE_HOME:-}"
  then
    printf '%s\n' "$XDG_CACHE_HOME/flyology-tla/toolchain"
  else
    printf '%s\n' "$HOME/.cache/flyology-tla/toolchain"
  fi
}

validate_root()
{
  candidate=$1
  case "$candidate" in
    /*) ;;
    *) die "toolchain root must be an absolute path" ;;
  esac
  case "$candidate" in
    /|*/|*/.|*/..|*//*) die "toolchain root must name a dedicated leaf directory" ;;
  esac
  case "$candidate" in
    */./*|*/../*) die "toolchain root must not contain . or .. components" ;;
  esac
  case "$candidate" in
    *"'"*) die "toolchain root must not contain a single quote" ;;
  esac
  case "$candidate" in
    *"
"*) die "toolchain root must not contain line breaks" ;;
  esac
  carriage_return=$(printf '\r_')
  carriage_return=${carriage_return%_}
  case "$candidate" in
    *"$carriage_return"*) die "toolchain root must not contain line breaks" ;;
  esac
  test ! -L "$candidate" || die "toolchain root must not be a symbolic link"
  candidate_parent=$(dirname -- "$candidate")
  test "$candidate_parent" != / ||
    die "toolchain root must not be a direct child of /"
  test "$candidate" != "$HOME" || die "toolchain root must not be HOME"
  if test -n "${XDG_CACHE_HOME:-}"
  then
    test "$candidate" != "$XDG_CACHE_HOME" ||
      die "toolchain root must not be XDG_CACHE_HOME"
  fi
}

digest()
{
  if command -v sha256sum >/dev/null 2>&1
  then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1
  then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    die "sha256sum or shasum is required"
  fi
}

platform()
{
  operating_system=$(uname -s)
  architecture=$(uname -m)
  case "$operating_system:$architecture" in
    Darwin:arm64) printf '%s\n' darwin-aarch64 ;;
    Linux:x86_64) printf '%s\n' linux-x86_64 ;;
    *) die "unsupported TLAPS platform: $operating_system $architecture" ;;
  esac
}

java_api_platform()
{
  case "$1" in
    darwin-aarch64) printf '%s\n' mac/aarch64 ;;
    linux-x86_64) printf '%s\n' linux/x64 ;;
    *) die "unsupported Java platform: $1" ;;
  esac
}

download()
{
  url=$1
  destination=$2
  case "$url" in
    https://api.github.com/repos/*/releases/assets/*)
      curl --fail --location --retry 3 --retry-delay 2 \
        --header 'Accept: application/octet-stream' \
        --output "$destination" "$url"
      ;;
    *)
      curl --fail --location --retry 3 --retry-delay 2 \
        --output "$destination" "$url"
      ;;
  esac
}

verify_expected_digest()
{
  file=$1
  expected=$2
  actual=$(digest "$file")
  test "$actual" = "$expected" ||
    die "SHA-256 mismatch for $file: expected $expected, got $actual"
}

write_receipt()
{
  receipt_root=$1
  selected_platform=$2
  java_archive_sha=$3
  java_binary_sha=$4
  tlapm_binary_sha=$5
  java_version=$6
  temporary_receipt=$receipt_root/receipt.json.tmp
  {
    printf '%s\n' '{'
    printf '%s\n' '  "format": "flyology.tla.toolchain-receipt/1",'
    printf '  "platform": "%s",\n' "$selected_platform"
    printf '%s\n' '  "tla_tools": {'
    printf '%s\n' '    "version": "1.8.0",'
    printf '%s\n' '    "revision": "1239539",'
    printf '    "sha256": "%s"\n' "$TLA_TOOLS_SHA256"
    printf '%s\n' '  },'
    printf '%s\n' '  "tlaps": {'
    printf '%s\n' '    "version": "1.6.0-pre",'
    printf '%s\n' '    "revision": "4600b24",'
    printf '    "tlapm_sha256": "%s"\n' "$tlapm_binary_sha"
    printf '%s\n' '  },'
    printf '%s\n' '  "java": {'
    printf '%s\n' '    "distribution": "Eclipse Temurin",'
    printf '%s\n' '    "feature_version": 21,'
    printf '    "resolved_version": "%s",\n' "$java_version"
    printf '    "archive_sha256": "%s",\n' "$java_archive_sha"
    printf '    "java_sha256": "%s"\n' "$java_binary_sha"
    printf '%s\n' '  }'
    printf '%s\n' '}'
  } >"$temporary_receipt"
  mv "$temporary_receipt" "$receipt_root/receipt.json"
}

install_toolchain()
{
  root=$1
  selected_platform=$(platform)
  case "$selected_platform" in
    darwin-aarch64)
      tlapm_url=$TLAPM_DARWIN_URL
      tlapm_archive_sha=$TLAPM_DARWIN_SHA256
      expected_tlapm_binary_sha=$TLAPM_DARWIN_BINARY_SHA256
      ;;
    linux-x86_64)
      tlapm_url=$TLAPM_LINUX_URL
      tlapm_archive_sha=$TLAPM_LINUX_SHA256
      expected_tlapm_binary_sha=
      ;;
  esac
  java_platform=$(java_api_platform "$selected_platform")
  java_os=${java_platform%/*}
  java_arch=${java_platform#*/}
  java_url=$TEMURIN_URL_BASE/$java_os/$java_arch/jre/hotspot/normal/eclipse

  parent=$(dirname -- "$root")
  mkdir -p "$parent"
  temporary_root=$(mktemp -d "$parent/.flyology-tla-install.XXXXXX")
  trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM
  mkdir -p "$temporary_root/root/lib" "$temporary_root/java" "$temporary_root/tlaps"

  download "$TLA_TOOLS_URL" "$temporary_root/tla2tools.jar"
  verify_expected_digest "$temporary_root/tla2tools.jar" "$TLA_TOOLS_SHA256"
  mv "$temporary_root/tla2tools.jar" "$temporary_root/root/lib/tla2tools.jar"

  download "$tlapm_url" "$temporary_root/tlapm.tar.gz"
  verify_expected_digest "$temporary_root/tlapm.tar.gz" "$tlapm_archive_sha"
  tar -xzf "$temporary_root/tlapm.tar.gz" -C "$temporary_root/tlaps"
  tlapm_binary=$(find "$temporary_root/tlaps" -type f -path '*/bin/tlapm' -perm -u+x | head -1)
  test -n "$tlapm_binary" || die "TLAPS archive did not contain bin/tlapm"
  tlapm_source=${tlapm_binary%/bin/tlapm}
  tlapm_binary_sha=$(digest "$tlapm_binary")
  if test -n "$expected_tlapm_binary_sha"
  then
    test "$tlapm_binary_sha" = "$expected_tlapm_binary_sha" ||
      die "extracted tlapm SHA-256 mismatch"
  fi
  mv "$tlapm_source" "$temporary_root/root/tlaps"

  download "$java_url" "$temporary_root/temurin.tar.gz"
  java_archive_sha=$(digest "$temporary_root/temurin.tar.gz")
  tar -xzf "$temporary_root/temurin.tar.gz" -C "$temporary_root/java"
  java_binary=$(find "$temporary_root/java" -type f -path '*/bin/java' -perm -u+x | head -1)
  test -n "$java_binary" || die "Temurin archive did not contain bin/java"
  java_source=${java_binary%/bin/java}
  java_binary_sha=$(digest "$java_binary")
  java_version=$("$java_binary" -XshowSettings:properties -version 2>&1 |
    awk -F'= ' '/^[[:space:]]*java.version = / {print $2; exit}')
  java_vendor=$("$java_binary" -XshowSettings:properties -version 2>&1 |
    awk -F'= ' '/^[[:space:]]*java.vendor = / {print $2; exit}')
  case "$java_version" in 21.*) ;; *) die "resolved Java is not feature version 21" ;; esac
  case "$java_vendor" in *Adoptium*) ;; *) die "resolved Java is not Eclipse Temurin" ;; esac
  case "$java_version" in
    *[!A-Za-z0-9._+-]*) die "resolved Java version contains unsafe receipt characters" ;;
  esac
  mv "$java_source" "$temporary_root/root/jre"

  write_receipt "$temporary_root/root" "$selected_platform" \
    "$java_archive_sha" "$java_binary_sha" "$tlapm_binary_sha" "$java_version"
  if test -e "$root"
  then
    verify_toolchain "$root" >/dev/null
    rm -rf "$root"
  fi
  mv "$temporary_root/root" "$root"
  trap - EXIT HUP INT TERM
  rm -rf "$temporary_root"
  verify_toolchain "$root"
}

receipt_value()
{
  key=$1
  receipt=$2
  sed -n "s/.*\"$key\": \"\([^\"]*\)\".*/\1/p" "$receipt" | tail -1
}

verify_toolchain()
{
  verify_root=$1
  test -f "$verify_root/receipt.json" || die "missing $verify_root/receipt.json"
  test -x "$verify_root/jre/bin/java" || die "missing Temurin java"
  test -f "$verify_root/lib/tla2tools.jar" || die "missing tla2tools.jar"
  test -x "$verify_root/tlaps/bin/tlapm" || die "missing tlapm"
  verify_expected_digest "$verify_root/lib/tla2tools.jar" "$TLA_TOOLS_SHA256"
  expected_java_sha=$(receipt_value java_sha256 "$verify_root/receipt.json")
  expected_tlapm_sha=$(receipt_value tlapm_sha256 "$verify_root/receipt.json")
  receipt_platform=$(receipt_value platform "$verify_root/receipt.json")
  test -n "$expected_java_sha" || die "receipt lacks java_sha256"
  test -n "$expected_tlapm_sha" || die "receipt lacks tlapm_sha256"
  test "$receipt_platform" = "$(platform)" || die "receipt platform does not match this host"
  grep -Fq '"revision": "1239539"' "$verify_root/receipt.json" ||
    die "receipt lacks pinned TLA+ Tools revision"
  grep -Fq '"revision": "4600b24"' "$verify_root/receipt.json" ||
    die "receipt lacks pinned TLAPS revision"
  verify_expected_digest "$verify_root/jre/bin/java" "$expected_java_sha"
  verify_expected_digest "$verify_root/tlaps/bin/tlapm" "$expected_tlapm_sha"
  java_version=$("$verify_root/jre/bin/java" -XshowSettings:properties -version 2>&1 |
    awk -F'= ' '/^[[:space:]]*java.version = / {print $2; exit}')
  java_vendor=$("$verify_root/jre/bin/java" -XshowSettings:properties -version 2>&1 |
    awk -F'= ' '/^[[:space:]]*java.vendor = / {print $2; exit}')
  case "$java_version" in 21.*) ;; *) die "installed Java is not feature version 21" ;; esac
  case "$java_vendor" in *Adoptium*) ;; *) die "installed Java is not Eclipse Temurin" ;; esac
  test "$(receipt_value resolved_version "$verify_root/receipt.json")" = "$java_version" ||
    die "installed Java version does not match receipt"
  if test "$(platform)" = darwin-aarch64
  then
    test "$expected_tlapm_sha" = "$TLAPM_DARWIN_BINARY_SHA256" ||
      die "installed tlapm is not the pinned macOS binary"
  else
    test "$("$verify_root/tlaps/bin/tlapm" --version)" = 4600b24 ||
      die "installed tlapm revision is not 4600b24"
  fi
  printf 'verified flyology TLA+ toolchain: %s\n' "$verify_root"
}

environment()
{
  environment_root=$1
  verify_toolchain "$environment_root" >/dev/null
  printf "export FLYOLOGY_TLA_TOOLCHAIN='%s'\n" "$environment_root"
  printf "export FLYOLOGY_TLA_JAVA='%s/jre/bin/java'\n" "$environment_root"
  printf "export FLYOLOGY_TLA_TLC_JAR='%s/lib/tla2tools.jar'\n" "$environment_root"
  printf "export FLYOLOGY_TLAPM='%s/tlaps/bin/tlapm'\n" "$environment_root"
}

command_name=${1:-help}
test "$#" -le 2 || die "too many toolchain arguments"
case "$command_name" in
  install|verify|env)
    root=${2:-$(default_root)}
    validate_root "$root"
    ;;
esac
case "$command_name" in
  install) install_toolchain "$root" ;;
  verify) verify_toolchain "$root" ;;
  env) environment "$root" ;;
  *)
    die "usage: flyology-tla toolchain install|verify|env [ABSOLUTE_ROOT]"
    ;;
esac
