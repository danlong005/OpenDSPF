#!/bin/bash
# OpenDSPF interactive runtime test runner
#
# Unlike run_tests.sh (which only diffs dspfc's compiled JSON), this drives
# actual runtime BEHAVIOR through ncurses: compiles a .dspf + a driver
# .rpgle with dspfc/rpgc, pipes a scripted keystroke sequence into the
# resulting program's stdin, and diffs its RESULT:-tagged DSPLY output
# against golden text. Things like AUTO-advance, field validation, or
# subfile paging only manifest via real keystrokes — a JSON-only test can't
# catch a regression in any of them.
#
# Driver .rpgle programs must DSPLY their results as `RESULT:<name>=<val>`
# (see TEST08_AUTO.rpgle) — the prefix lets the harness pull real output
# out of the raw ncurses screen-paint noise unambiguously (a bare "ABC"
# DSPLY value can otherwise collide with coincidental screen content byte
# for byte; "RESULT:FLD1=ABC" cannot).

set -e

DSPFC="${DSPFC:-./dspfc}"
RPGC="${RPGC:-$([ -x ../OpenRPG/rpgc ] && echo ../OpenRPG/rpgc || which rpgc 2>/dev/null || echo ../OpenRPG/rpgc)}"
TESTDIR="tests"
EXPECTED="$TESTDIR/expected_interactive"
TMPDIR="/tmp/dspfc_interactive_test"
PASS=0
FAIL=0
FAILURES=""

TIMEOUT_CMD="timeout 10"
if ! command -v timeout >/dev/null 2>&1; then
    if command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD="gtimeout 10"
    else TIMEOUT_CMD=""; fi
fi

mkdir -p "$TMPDIR" "$EXPECTED"

if [ -t 1 ]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
else
    GREEN=''; RED=''; NC=''
fi

if [ ! -x "$RPGC" ]; then
    echo "SKIP: rpgc not found (set RPGC=/path/to/rpgc). Interactive tests need it to compile the driver .rpgle programs."
    exit 0
fi

# Strips ncurses/terminal escape sequences (CSI, charset-designation, and
# 2-byte ESC sequences), then pulls out RESULT:name=value tokens.
strip_and_extract() {
    perl -pe 's/\x1b\[[0-9;?]*[a-zA-Z=<>]//g; s/\x1b[()][0-9A-Za-z]//g; s/\x1b[=><]//g; s/\x0f//g' \
        | grep -oE 'RESULT:[A-Za-z0-9_]+=[A-Za-z0-9]*'
}

# Pulls distinct terminal row numbers (1-based) that were cursor-positioned
# to within [lo,hi] out of the RAW (unstripped) output — i.e. rows ncurses
# actually wrote to via a CUP escape (ESC[row;colH). Used to confirm a
# message-subfile area accumulated multiple rows rather than overwriting
# the same one each time (see test09).
extract_touched_rows() {
    local lo="$1" hi="$2"
    grep -aoE '\[[0-9]+;[0-9]+H' \
        | sed -E 's/\[([0-9]+);.*/\1/' \
        | awk -v lo="$lo" -v hi="$hi" '$1>=lo && $1<=hi' \
        | sort -un \
        | sed 's/^/MSGROW:/'
}

run_interactive_test() {
    local label="$1"
    local dspf_src="$2"
    local rpg_src="$3"
    local keys="$4"      # printf-format keystroke string, e.g. 'ABC\t123\r'
    local golden="$5"
    local row_range="$6" # optional "lo-hi": also assert which rows got touched

    printf "%-55s " "$label"

    local base; base=$(basename "$rpg_src" .rpgle)
    local exe="$TMPDIR/$base"

    if ! "$DSPFC" "$dspf_src" -o "$TESTDIR" > "$TMPDIR/${base}_dspfc_err.txt" 2>&1; then
        echo -e "${RED}FAIL${NC} (dspfc error)"
        sed 's/^/    /' "$TMPDIR/${base}_dspfc_err.txt"
        FAIL=$((FAIL + 1)); FAILURES="$FAILURES\n  $label"
        return
    fi

    if ! "$RPGC" "$rpg_src" -o "$exe" > "$TMPDIR/${base}_rpgc_err.txt" 2>&1; then
        echo -e "${RED}FAIL${NC} (rpgc error)"
        sed 's/^/    /' "$TMPDIR/${base}_rpgc_err.txt"
        FAIL=$((FAIL + 1)); FAILURES="$FAILURES\n  $label"
        return
    fi

    local raw="$TMPDIR/${base}.raw"
    local actual="$TMPDIR/${base}.actual"
    # Run from $TESTDIR: the compiled program looks for its .dspfd relative
    # to its own working directory at runtime, not next to the exe. (dspfc
    # also had to write the .dspfd there, not $TMPDIR, since rpgc's own
    # WORKSTN pre-pass looks for it next to the .rpgle source at compile
    # time — clean those generated files up below so repeated runs don't
    # leave build output sitting in the source tree.)
    (cd "$TESTDIR" && printf "$keys" | $TIMEOUT_CMD "$exe") > "$raw" 2>&1 || true
    rm -f "$TESTDIR/${base}.dspfd" "$TESTDIR/${base}_dspf.h"
    strip_and_extract < "$raw" > "$actual"
    if [ -n "$row_range" ]; then
        extract_touched_rows "${row_range%-*}" "${row_range#*-}" < "$raw" >> "$actual"
    fi

    if diff -q --strip-trailing-cr "$actual" "$golden" > /dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} (output mismatch)"
        diff --strip-trailing-cr "$golden" "$actual" | sed 's/^/    /'
        FAIL=$((FAIL + 1)); FAILURES="$FAILURES\n  $label"
    fi
}

# ── test08: AUTO ──────────────────────────────────────────────────────────
# FLD1 has AUTO (3 chars); FLD2/FLD3 don't. Types "ABC" (fills FLD1 -> AUTO
# advances to FLD2), "XYZ" (fills FLD2 -> no AUTO, cursor must NOT advance),
# explicit Tab to FLD3, then "123". If AUTO were unconditional (the bug this
# guards against), the second fill would *also* auto-advance past FLD3
# before "123" is typed, and FLD3 would come back empty.
run_interactive_test \
    "test08: AUTO advances only when keyword present" \
    "$TESTDIR/TEST08_AUTO.dspf" "$TESTDIR/TEST08_AUTO.rpgle" \
    'ABCXYZ\t123\r' \
    "$EXPECTED/TEST08_AUTO.out"

# ── test09: ERRSFL / SFLMSGRCD ───────────────────────────────────────────
# SFLMSGRCD(20) reserves row 20+ for the message subfile. Two invalid
# attempts ("X", Backspace, "Y") must each land on a distinct row there
# (accumulating — the point of ERRSFL) rather than both landing on the same
# row (the pre-ERRSFL single-status-line behavior this replaces for records
# that opt in), then a valid attempt ("A") succeeds.
run_interactive_test \
    "test09: ERRSFL accumulates messages at distinct rows" \
    "$TESTDIR/TEST09_ERRSFL.dspf" "$TESTDIR/TEST09_ERRSFL.rpgle" \
    'X\r\bY\r\bA\r' \
    "$EXPECTED/TEST09_ERRSFL.out" \
    "20-23"

# ── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -ne 0 ]; then
    echo -e "${RED}Failed tests:${NC}$FAILURES"
    exit 1
fi
