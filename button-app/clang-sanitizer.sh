#!/usr/bin/env bash
# clang-sanitizer.sh - make an ESP-IDF compile_commands.json readable by clang-tidy.
#
# ESP-IDF records the command it gives xtensa-esp32-elf-gcc. clang rejects three things:
#
#   1. the xtensa machine options      -mlongcalls, -mtext-section-literals
#   2. the GCC code generation family  -fno-tree-switch-conversion, -fno-shrink-wrap, ...
#   3. the target triple               --target=xtensa-esp32-unknown-elf
#
# Two of those often travel in a response file, @".../build/toolchain/cflags", which the
# database only references by path. The script expands every @file first, then strips the
# flag families and the triple, replaces the compiler with clang and a 32 bit stand-in
# target, and adds the header directories that GCC finds next to its own binary, plus the
# per-chip xtensa configuration directory from the IDF tree, which clang cannot find.
#
# Why i686: clang has no xtensa backend. i686-unknown-linux-gnu supplies a 32 bit,
# little-endian ILP32 stand-in and, unlike riscv32, recognizes Xtensa-style register
# constraint names used by ESP-IDF inline assembly. The preprocessor state is
# made to match the real build: __XTENSA__ and __XTENSA_EL__ are defined and __riscv is
# dropped, so the IDF headers and the C library take the xtensa branches.
#
# Usage:
#   clang-sanitizer.sh [build/compile_commands.json] [-o OUT] [--in-place]
#
# Default output: <input dir>/clangdb/compile_commands.json, so clang-tidy finds it with
# -p build/clangdb and the original database stays untouched.

set -euo pipefail

PROG=${0##*/}
TARGET=i686-unknown-linux-gnu
IN=build/compile_commands.json
OUT=
IN_PLACE=0
VERBOSE=0

log() {
  if [ "$VERBOSE" -eq 1 ]; then
    echo "$PROG: $*"
  fi
}

usage() {
  cat <<'EOF'
Usage:
  clang-sanitizer.sh [build/compile_commands.json] [-o OUT]
  clang-sanitizer.sh --in-place [build/compile_commands.json]

Defaults: input build/compile_commands.json, output <input dir>/clangdb/compile_commands.json,
because clang-tidy reads that name from -p <dir>. The input is never written unless you
pass --in-place, which keeps <file>.bak.

Options:
  -o, --output PATH   write the sanitized database here
  -i, --in-place      rewrite the input, keeping a .bak copy
  -t, --target TRIPLE stand-in target, default i686-unknown-linux-gnu
  -v, --verbose       print progress and removed-flags output
  -h, --help          this text
EOF
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case $1 in
    -o|--output)   OUT=${2:?-o needs a path}; shift 2 ;;
    -i|--in-place) IN_PLACE=1; shift ;;
    -t|--target)   TARGET=${2:?-t needs a triple}; shift 2 ;;
    -v|--verbose)  VERBOSE=1; shift ;;
    -h|--help)     usage 0 ;;
    -*)            echo "$PROG: unknown option $1" >&2; usage 1 ;;
    *)             IN=$1; shift ;;
  esac
done

command -v jq >/dev/null || { echo "$PROG: jq is not installed" >&2; exit 1; }
[ -f "$IN" ] || { echo "$PROG: no such file: $IN" >&2; exit 1; }

if [ "$IN_PLACE" -eq 1 ]; then
  OUT=$IN
elif [ -z "$OUT" ]; then
  OUT=$(dirname "$IN")/clangdb/compile_commands.json
fi
if [ "$IN_PLACE" -eq 0 ] && [ "$(realpath -m -- "$OUT")" = "$(realpath -m -- "$IN")" ]; then
  echo "$PROG: output is the input ($OUT). Use --in-place, or -o with another path." >&2
  exit 1
fi
[ -d "$OUT" ] && { echo "$PROG: $OUT is a directory, -o needs a file path" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"

COUNT=$(jq 'if type == "array" then length else error("not a JSON array") end' "$IN")
WORK=$(mktemp "${TMPDIR:-/tmp}/clang-sanitizer.XXXXXX")
trap 'rm -f "$WORK" "$WORK".*' EXIT

# 1. Expand response files. ESP-IDF keeps the common flags in a shared file that the
#    database references as @path, and clang expands it after us.
cp "$IN" "$WORK"
mapfile -t RSPS < <(
  jq -r '.[] | .command // (.arguments | join(" "))' "$IN" \
  | grep -oE '@"[^"]+"|@[^[:space:]]+' \
  | sed -E 's/^@//; s/^"//; s/"$//' | sort -u || true
)
for rsp in "${RSPS[@]:-}"; do
  [ -n "$rsp" ] || continue
  rsp_ref=$rsp
  if [ ! -f "$rsp" ] && [[ "$rsp" != /* ]]; then
    while IFS= read -r dir; do
      [ -n "$dir" ] || continue
      if [ -f "$dir/$rsp" ]; then
        rsp="$dir/$rsp"
        break
      fi
    done < <(jq -r '.[].directory // empty' "$WORK")
  fi
  if [ ! -f "$rsp" ]; then
    echo "$PROG: response file not found: $rsp" >&2
    continue
  fi
  body=$(tr '\n' ' ' < "$rsp" | tr -s '[:space:]' ' ')
  jq --arg lit "@\"$rsp_ref\"" --arg lit2 "@$rsp_ref" --arg rep " $body " '
    def rep($a; $b): split($a) | join($b);
    map(
      if has("command") then
        .command |= (rep($lit; $rep) | rep($lit2; $rep))
      else .
      end
      |
      if has("arguments") then
        .arguments |= (
          reduce .[] as $arg ([];
            if $arg == $lit or $arg == $lit2 then
              . + ($rep | split(" ") | map(select(length > 0)))
            else
              . + [$arg]
            end
          )
        )
      else .
      end
    )
  ' "$WORK" > "$WORK.rsp" && mv "$WORK.rsp" "$WORK"
  log "inlined $rsp"
done

# 2. The compiler's own header directories. GCC looks for its C library and its builtin
#    headers next to its own binary, so clang reports stdio.h, stdlib.h, inttypes.h and
#    stdbool.h as missing. Ask the compiler for its search list and pass the same list on.
CC0=$(jq -r '.[0] | .command // (.arguments | join(" "))' "$WORK" | awk '{print $1}')
INCS=()
if [ -n "$CC0" ] && [ -x "$CC0" ]; then
  while IFS= read -r d; do
    if [ -n "$d" ] && [ -d "$d" ]; then INCS+=("$d"); fi
  done < <("$CC0" -E -v -x c /dev/null 2>&1 \
    | sed -n '/#include <\.\.\.> search starts here:/,/End of search list\./p' \
    | sed '1d;$d' | sed 's/^ *//')
fi
if [ "${#INCS[@]}" -eq 0 ]; then
  log "no compiler include directories found, C library headers may be missing"
fi

# 2b. ESP-IDF v6 links against picolibc, which the toolchain keeps beside its newlib
#     include. Prefer it and drop the newlib directory the compiler reported.
FAM=$(basename "$CC0"); FAM=${FAM%%-*}
TOOLS_ROOT=$(printf '%s' "$CC0" | sed -E 's#/tools/.*#/tools#')
PICO=
if [ "$TOOLS_ROOT" != "$CC0" ]; then
  for d in "$TOOLS_ROOT/$FAM-esp-elf"/*/"$FAM-esp-elf"/picolibc/include; do
    if [ -f "$d/stdio.h" ]; then PICO=$d; break; fi
  done
fi
if [ -n "$PICO" ]; then
  KEEP=()
  for d in ${INCS[@]+"${INCS[@]}"}; do
    if [ -f "$d/sys/features.h" ]; then continue; fi
    KEEP+=("$d")
  done
  INCS=("$PICO" ${KEEP[@]+"${KEEP[@]}"})
  log "C library headers from $PICO"
fi

# 3. The xtensa configuration headers. An xtensa build gets them from the IDF tree, one
#    directory per chip. Add it only when the database does not already carry it.
IDFROOT=$( { jq -r '.[] | .command // (.arguments | join(" "))' "$WORK" \
  | grep -oE '(^|[[:space:]])-I[^[:space:]]+/components/' \
  | sed -E 's/.*-I//; s#/components/$##' | sed -n '1p'; } || true)
PREINCS=()
if [ -n "$IDFROOT" ] && ! jq -r '.[] | .command // (.arguments | join(" "))' "$WORK" \
     | grep -qE "components/xtensa/[a-z0-9]+/include"; then
  for d in "$IDFROOT"/components/xtensa/*/include; do
    if [ -f "$d/xtensa/config/tie.h" ]; then PREINCS+=("$d"); break; fi
  done
fi

INCSJSON=$(jq -cn '$ARGS.positional | map(select(. != ""))' --args "${INCS[@]:-}")
PREJSON=$(jq -cn '$ARGS.positional | map(select(. != ""))' --args "${PREINCS[@]:-}")
log "-isystem $INCSJSON"
log "-I $PREJSON"

# 4. Rewrite every entry.
FILTER='
def bad: test("^-(m|f)") or test("^-Werror") or test("^--?target=");
def suppress:
  if test("-Wno-unknown-warning-option") then . else . + " -Wno-unknown-warning-option" end;
def addi($i):
  if $i == "" or contains($i) then . else . + " -isystem " + $i end;
def sysinc: reduce ($incs[]) as $i (. ; addi($i));
def addargv:
  reduce ($incs[]) as $i (. ; if index($i) then . else . + ["-isystem", $i] end);
def addi_I($i):
  if $i == "" or contains($i) then . else . + " -I" + $i end;
def preinc: reduce ($pre[]) as $i (. ; addi_I($i));
def preargv:
  reduce ($pre[]) as $i (. ; if index($i) then . else . + ["-I", $i] end);
def clean_command:
  gsub("([[:space:]])-target[[:space:]]+[^[:space:]]+"; "")
  | gsub("([[:space:]])-target=[^[:space:]]+"; "")
  | gsub("([[:space:]])--target=[^[:space:]]+"; "")
  | sub("^\\s*[^[:space:]]+"; "clang --target=" + $target)
  | gsub("([[:space:]])-m[^[:space:]]*"; "")
  | gsub("([[:space:]])-f[^[:space:]]*"; "")
  | gsub("([[:space:]])-Werror[^[:space:]]*"; "")
  | suppress | sysinc | preinc | . + " " + $defs;
def clean_arguments:
  .[1:] as $rest
  | reduce range(0; $rest | length) as $i ({out: [], skip: false};
      if .skip then .skip = false
      elif $rest[$i] == "-target" then .skip = true
      elif ($rest[$i] | bad) then .
      else .out += [$rest[$i]] end)
  | .out;
map(
  if has("arguments") then
    .arguments as $a
    | .arguments = (["clang", ("--target=" + $target)] + ($a | clean_arguments)
                    + (if ($a | index("-Wno-unknown-warning-option")) then []
                       else ["-Wno-unknown-warning-option"] end)
                    | addargv | preargv
                    | . + $defargv)
  elif has("command") then
    .command |= clean_command
  else . end
)
'

DEFS='-D__XTENSA__ -D__XTENSA_EL__ -U__riscv'
DEFARGV='["-D__XTENSA__", "-D__XTENSA_EL__", "-U__riscv"]'
jq --arg target "$TARGET" --argjson incs "$INCSJSON" --argjson pre "$PREJSON" \
   --arg defs "$DEFS" --argjson defargv "$DEFARGV" "$FILTER" "$WORK" > "$OUT.tmp"

NEW_COUNT=$(jq 'length' "$OUT.tmp")
[ "$COUNT" = "$NEW_COUNT" ] || { echo "$PROG: entry count changed $COUNT -> $NEW_COUNT" >&2; exit 1; }
if jq -r '.[] | .command // (.arguments | join(" "))' "$OUT.tmp" \
   | grep -qE -- '--target=xtensa|(^|[[:space:]])[^[:space:]]*xtensa[^[:space:]]*-gcc'; then
  echo "$PROG: an xtensa compiler or triple survived, inspect $OUT.tmp" >&2
  exit 1
fi
if jq -r '.[] | .command // (.arguments | join(" "))' "$OUT.tmp" \
   | grep -qE '(^|[[:space:]])-(m|f)[a-z]'; then
  echo "$PROG: a machine or code generation flag survived, inspect $OUT.tmp" >&2
  exit 1
fi

if [ "$IN_PLACE" -eq 1 ] && [ ! -e "$IN.bak" ]; then
  cp "$IN" "$IN.bak"
  log "original kept as $IN.bak"
fi
mv "$OUT.tmp" "$OUT"

log "$COUNT entries -> $OUT (target $TARGET)"
echo "-p $(dirname "$OUT")"

REMOVED=$(jq -r '.[] | .command // (.arguments | join(" "))' "$WORK" \
  | grep -oE '(^|[[:space:]])(-m[^[:space:]]*|-f[^[:space:]]*|-Werror[^[:space:]]*|--target=xtensa[^[:space:]]*)' \
  | sed -E 's/^[[:space:]]+//' || true)
if [ -n "$REMOVED" ]; then
  log "flags removed"
  if [ "$VERBOSE" -eq 1 ]; then
    printf '%s\n' "$REMOVED" | sort | uniq -c | sort -rn | sed 's/^/  /'
  fi
else
  log "nothing to remove, the input was already clean"
fi
