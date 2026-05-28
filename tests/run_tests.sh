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
    if ! "$DSPFC" "$src" -o "$TMPDIR" >/dev/null 2>&1; then
        echo -e "${RED}FAIL${NC} (dspfc error)"
        FAIL=$((FAIL + 1))
        FAILURES="$FAILURES\n  $label"
        return
    fi

    if diff -q "$out" "$golden" >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} (output mismatch)"
        diff "$golden" "$out" | head -20
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

# ── DDS A-spec tests ──────────────────────────────────────────────────────────
run_test "test04: DDS subfile (SFL/SFLCTL/option indicators)" \
    "$TESTDIR/test04_dds_subfile.dds"   "$EXPECTED/test04_dds_subfile.dspfd"

run_test "test05: DDS — CUSTMENU (both formats produce identical output)" \
    "$TESTDIR/CUSTMENU.dds"             "$TESTDIR/CUSTMENU.dspfd"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -ne 0 ]; then
    echo -e "${RED}Failed tests:${NC}$FAILURES"
    exit 1
fi
