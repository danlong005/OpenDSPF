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

# Compiles the same record definition from both its free-format and
# fixed-format source, then diffs the JSON after normalising the
# filename-derived "name" field — proves both frontends produce identical
# output for the same keyword, rather than only ever exercising it through
# this compiler's own free-format dialect (real DDS is fixed-format; the
# free-format grammar is this project's own invention). Generalises the
# same idea test05 (CUSTMENU, below) already used one-off.
run_fixed_parity_test() {
    local label="$1"
    local free_src="$2"
    local fixed_src="$3"

    printf "%-45s " "$label"

    local free_base; free_base=$(basename "$free_src" .dspf)
    local fixed_base; fixed_base=$(basename "$fixed_src" .dspf)
    local err1 err2
    if ! err1=$("$DSPFC" "$free_src" -o "$TMPDIR" 2>&1 >/dev/null); then
        echo -e "${RED}FAIL${NC} (dspfc error, free-format)"
        [ -n "$err1" ] && echo "$err1" | sed 's/^/    /'
        FAIL=$((FAIL + 1)); FAILURES="$FAILURES\n  $label"
        return
    fi
    if ! err2=$("$DSPFC" "$fixed_src" -o "$TMPDIR" 2>&1 >/dev/null); then
        echo -e "${RED}FAIL${NC} (dspfc error, fixed-format)"
        [ -n "$err2" ] && echo "$err2" | sed 's/^/    /'
        FAIL=$((FAIL + 1)); FAILURES="$FAILURES\n  $label"
        return
    fi

    sed "s/\"$fixed_base\"/\"$free_base\"/g" \
        "$TMPDIR/$fixed_base.dspfd" > "$TMPDIR/${fixed_base}_norm.dspfd"

    if diff -q --strip-trailing-cr "$TMPDIR/$free_base.dspfd" "$TMPDIR/${fixed_base}_norm.dspfd" >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"; PASS=$((PASS + 1))
    else
        echo -e "${RED}FAIL${NC} (output mismatch)"
        diff --strip-trailing-cr "$TMPDIR/$free_base.dspfd" "$TMPDIR/${fixed_base}_norm.dspfd" | head -20
        FAIL=$((FAIL + 1)); FAILURES="$FAILURES\n  $label"
    fi
}

# Compiles a deliberately-invalid source file and checks dspfc's exit code
# and stderr message, rather than any JSON output — for the SFLPAG/SFLSIZ
# and off-screen-position sanity checks, where the diagnostic itself is
# the thing under test.
run_diag_test() {
    local label="$1"
    local src="$2"
    local expect_exit="$3"    # 0 or 1
    local expect_pattern="$4" # grep -F pattern that must appear in stderr

    printf "%-45s " "$label"

    local err rc
    rc=0
    err=$("$DSPFC" "$src" -o "$TMPDIR" 2>&1 >/dev/null) || rc=$?

    if [ "$rc" != "$expect_exit" ]; then
        echo -e "${RED}FAIL${NC} (expected exit $expect_exit, got $rc)"
        echo "$err" | sed 's/^/    /'
        FAIL=$((FAIL + 1)); FAILURES="$FAILURES\n  $label"
        return
    fi
    if ! echo "$err" | grep -qF "$expect_pattern"; then
        echo -e "${RED}FAIL${NC} (missing expected message)"
        echo "    expected to contain: $expect_pattern"
        echo "$err" | sed 's/^/    /'
        FAIL=$((FAIL + 1)); FAILURES="$FAILURES\n  $label"
        return
    fi
    echo -e "${GREEN}PASS${NC}"
    PASS=$((PASS + 1))
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

run_fixed_parity_test "test08b: AUTO (fixed-format == free-format output)" \
    "$TESTDIR/TEST08_AUTO.dspf" "$TESTDIR/TEST08_AUTO_fixed.dspf"

run_test "test09: ERRSFL / SFLMSGRCD keywords" \
    "$TESTDIR/TEST09_ERRSFL.dspf"           "$EXPECTED/TEST09_ERRSFL.dspfd"

run_fixed_parity_test "test09b: ERRSFL / SFLMSGRCD (fixed-format == free-format)" \
    "$TESTDIR/TEST09_ERRSFL.dspf" "$TESTDIR/TEST09_ERRSFL_fixed.dspf"

run_test "test10: KEY PAGEUP/PAGEDOWN (fixed-format ROLLUP/ROLLDOWN alias)" \
    "$TESTDIR/TEST10_PAGEKEY.dspf"          "$EXPECTED/TEST10_PAGEKEY.dspfd"

# test10b uses its own golden, not the parity pattern: real DDS record names
# cap at 10 chars, and PAGEKEYTEST (11) overflows the fixed-format record-
# name column, so the fixed-format twin is PAGEKEYTST — legitimately not a
# byte-identical name between the two.
run_test "test10b: ROLLUP/ROLLDOWN (real fixed-format DDS keyword names)" \
    "$TESTDIR/TEST10_PAGEKEY_fixed.dspf"    "$EXPECTED/TEST10_PAGEKEY_fixed.dspfd"

run_test "test11: CLRL(begline endline) partial-screen clear" \
    "$TESTDIR/TEST11_CLRL.dspf"             "$EXPECTED/TEST11_CLRL.dspfd"

run_fixed_parity_test "test11b: CLRL (fixed-format == free-format output)" \
    "$TESTDIR/TEST11_CLRL.dspf" "$TESTDIR/TEST11_CLRL_fixed.dspf"

run_test "test12: DATE/TIME/TIMESTAMP field types (L/T/Z)" \
    "$TESTDIR/TEST12_DATETIME.dspf"         "$EXPECTED/TEST12_DATETIME.dspfd"

run_fixed_parity_test "test12b: L/T/Z (fixed-format == free-format output)" \
    "$TESTDIR/TEST12_DATETIME.dspf" "$TESTDIR/TEST12_DATETIME_fixed.dspf"

run_test "test13: ALIAS(name) keyword" \
    "$TESTDIR/TEST13_ALIAS.dspf"            "$EXPECTED/TEST13_ALIAS.dspfd"

run_fixed_parity_test "test13b: ALIAS (fixed-format == free-format output)" \
    "$TESTDIR/TEST13_ALIAS.dspf" "$TESTDIR/TEST13_ALIAS_fixed.dspf"

run_test "test14: COLHDG('text') keyword (quoted-string generic keyword arg)" \
    "$TESTDIR/TEST14_COLHDG.dspf"           "$EXPECTED/TEST14_COLHDG.dspfd"

run_fixed_parity_test "test14b: COLHDG (fixed-format == free-format output)" \
    "$TESTDIR/TEST14_COLHDG.dspf" "$TESTDIR/TEST14_COLHDG_fixed.dspf"

run_test "test15: CHANGE / BLANKS keywords (record- and field-level)" \
    "$TESTDIR/TEST15_CHANGE_BLANKS.dspf"    "$EXPECTED/TEST15_CHANGE_BLANKS.dspfd"

run_test "test16: subfile per-row OPTION field (VALUES on a SFL field)" \
    "$TESTDIR/TEST16_SFLOPTION.dspf"        "$EXPECTED/TEST16_SFLOPTION.dspfd"

run_test "test17: subfile with no editable fields (HIDDEN SFLRCDNBR)" \
    "$TESTDIR/TEST17_SFLSELECT.dspf"        "$EXPECTED/TEST17_SFLSELECT.dspfd"

run_test "test18: SFLNXTCHG (subfile next changed) keyword" \
    "$TESTDIR/TEST18_SFLNXTCHG.dspf"        "$EXPECTED/TEST18_SFLNXTCHG.dspfd"

run_diag_test "test19: SFLPAG > SFLSIZ is a hard compile error" \
    "$TESTDIR/test19_sflsiz_error.dspf" 1 \
    "SFLPAG(20) exceeds SFLSIZ(10)"

run_test "test20: field/literal outside SCREEN SIZE (warns, still compiles)" \
    "$TESTDIR/test20_field_bounds_warning.dspf" "$EXPECTED/test20_field_bounds_warning.dspfd"

run_diag_test "test20b: field bounds check reports the right offender" \
    "$TESTDIR/test20_field_bounds_warning.dspf" 0 \
    "field OFFSCREEN row 30 is outside SCREEN SIZE(24 80)"

# test15b uses its own golden, not the parity pattern: BLANKS's optional
# comment text pushes past the 36-char field-line keyword budget (real DDS
# has no field-level keyword continuation line — only record-level), so the
# fixed-format twin uses a shorter message.
run_test "test15b: CHANGE / BLANKS (fixed-format, real DDS column limits)" \
    "$TESTDIR/TEST15_CHANGE_BLANKS_fixed.dspf" "$EXPECTED/TEST15_CHANGE_BLANKS_fixed.dspfd"

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
