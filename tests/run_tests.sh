#!/bin/bash
# OpenDSPF compiler test runner
# Compiles each test source file and diffs the JSON descriptor against golden output.

set -e

DSPFC="${DSPFC:-./dspfc}"
TESTDIR="tests"
EXPECTED="$TESTDIR/expected"
TMPDIR="/tmp/dspfc_test"
PASS=0
FAIL=0
FAILURES=""

mkdir -p "$TMPDIR"

if [ -t 1 ]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
else
    GREEN=''; RED=''; NC=''
fi

run_test() {
    local label="$1"
    local src="$2"
    local golden="$3"

    printf "%-45s " "$label"

    local out="$TMPDIR/$(basename "$golden")"
    local err
    if ! err=$("$DSPFC" "$src" -o "$TMPDIR" 2>&1 >/dev/null); then
        echo -e "${RED}FAIL${NC} (dspfc error)"
        [ -n "$err" ] && echo "$err" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        FAILURES="$FAILURES\n  $label"
        return
    fi

    if diff -q --strip-trailing-cr "$out" "$golden" >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} (output mismatch)"
        diff --strip-trailing-cr "$golden" "$out" | head -20
        FAIL=$((FAIL + 1))
        FAILURES="$FAILURES\n  $label"
    fi
}

# ── Free-format .dspf tests ───────────────────────────────────────────────────
run_test "test01: basic record (literals/fields/keys/color)" \
    "$TESTDIR/test01_basic.dspf"        "$EXPECTED/test01_basic.dspfd"

run_test "test02: subfile (SUBFILE/SFLCTL/SFLPAG/SFLSIZ/EDTCDE)" \
    "$TESTDIR/test02_subfile.dspf"      "$EXPECTED/test02_subfile.dspfd"

run_test "test03: conditioning indicators (COND(*INxx) on fields and literals)" \
    "$TESTDIR/test03_cond.dspf"         "$EXPECTED/test03_cond.dspfd"

# ── Fixed-format tests ────────────────────────────────────────────────────────
run_test "test04: fixed-format subfile (SFL/SFLCTL/option indicators)" \
    "$TESTDIR/test04_fixed_subfile.dspf"   "$EXPECTED/test04_fixed_subfile.dspfd"

run_test "test06: conditional DSPATR (duplicate field, mutually exclusive COND)" \
    "$TESTDIR/test06_cond_dspatr.dspf"     "$EXPECTED/test06_cond_dspatr.dspfd"

run_test "test07: field validation keywords (VALUES/RANGE/COMP)" \
    "$TESTDIR/test07_validate.dspf"        "$EXPECTED/test07_validate.dspfd"

run_test "test08: AUTO keyword (field-level, generic keyword passthrough)" \
    "$TESTDIR/TEST08_AUTO.dspf"             "$EXPECTED/TEST08_AUTO.dspfd"

run_test "test09: ERRSFL / SFLMSGRCD keywords" \
    "$TESTDIR/TEST09_ERRSFL.dspf"           "$EXPECTED/TEST09_ERRSFL.dspfd"

run_test "test10: KEY PAGEUP/PAGEDOWN (fixed-format ROLLUP/ROLLDOWN alias)" \
    "$TESTDIR/TEST10_PAGEKEY.dspf"          "$EXPECTED/TEST10_PAGEKEY.dspfd"

# test05: compile both formats and compare their outputs (basename-normalised).
# Free-format CUSTMENU.dspf produces "CUSTMENU"; fixed-format CUSTMENU_fixed.dspf
# produces "CUSTMENU_fixed" — normalise before diff.
printf "%-45s " "test05: CUSTMENU (free-format == fixed-format output)"
rc1=0; rc2=0
if ! err1=$("$DSPFC" "$TESTDIR/CUSTMENU.dspf"       -o "$TMPDIR" 2>&1 >/dev/null); then rc1=1; fi
if ! err2=$("$DSPFC" "$TESTDIR/CUSTMENU_fixed.dspf" -o "$TMPDIR" 2>&1 >/dev/null); then rc2=1; fi
if [ $rc1 -eq 0 ] && [ $rc2 -eq 0 ]; then
    sed 's/"CUSTMENU_fixed"/"CUSTMENU"/g' \
        "$TMPDIR/CUSTMENU_fixed.dspfd" > "$TMPDIR/CUSTMENU_fixed_norm.dspfd"
    if diff -q --strip-trailing-cr "$TMPDIR/CUSTMENU.dspfd" "$TMPDIR/CUSTMENU_fixed_norm.dspfd" >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"; PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} (output mismatch)"
        diff --strip-trailing-cr "$TMPDIR/CUSTMENU.dspfd" "$TMPDIR/CUSTMENU_fixed_norm.dspfd"
        FAIL=$((FAIL + 1)); FAILURES="$FAILURES\n  test05: CUSTMENU format parity"
    fi
else
    echo -e "${RED}FAIL${NC} (dspfc error)"
    [ -n "$err1" ] && echo "$err1" | sed 's/^/    /'
    [ -n "$err2" ] && echo "$err2" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
    FAILURES="$FAILURES\n  test05: CUSTMENU format parity"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -ne 0 ]; then
    echo -e "${RED}Failed tests:${NC}$FAILURES"
    exit 1
fi
