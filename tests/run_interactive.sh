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
        | grep -oE 'RESULT:[A-Za-z0-9_]+=[A-Za-z0-9.-]*'
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

# Counts full-screen-clear escapes (ESC[2J) in the RAW output. A byte-stream
# capture can't show "this text got cleared" directly — clearing something
# doesn't retroactively remove its earlier bytes from the log, it only
# changes what gets sent next — so partial vs. full clear (CLRL vs. the
# default) has to be distinguished by *how many* full-screen clears
# happened, not by which text is or isn't present (see test11).
count_full_clears() {
    grep -acF $'\x1b[2J'
}

run_interactive_test() {
    local label="$1"
    local dspf_src="$2"
    local rpg_src="$3"
    local keys="$4"      # printf-format keystroke string, e.g. 'ABC\t123\r'
    local golden="$5"
    local row_range="$6"    # optional "lo-hi": also assert which rows got touched
    local check_clears="$7" # optional "1": also assert full-clear count as CLEARCOUNT:n

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
    if [ "$check_clears" = "1" ]; then
        echo "CLEARCOUNT:$(count_full_clears < "$raw")" >> "$actual"
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

# ── test10: KEY PAGEUP/PAGEDOWN as exit keys ─────────────────────────────
# \x1b[5~ / \x1b[6~ are this terminal's (xterm-256color) raw byte sequences
# for PageUp/PageDown, confirmed against KEY_PPAGE/KEY_NPAGE directly before
# writing this. A plain (non-subfile) record has nothing to scroll, so
# these only do anything if the record declares KEY PAGEUP/PAGEDOWN.
run_interactive_test \
    "test10a: PAGEUP sets its declared indicator" \
    "$TESTDIR/TEST10_PAGEKEY.dspf" "$TESTDIR/TEST10_PAGEKEY.rpgle" \
    '\x1b[5~' \
    "$EXPECTED/TEST10_PAGEKEY_up.out"

run_interactive_test \
    "test10b: PAGEDOWN sets its declared indicator" \
    "$TESTDIR/TEST10_PAGEKEY.dspf" "$TESTDIR/TEST10_PAGEKEY.rpgle" \
    '\x1b[6~' \
    "$EXPECTED/TEST10_PAGEKEY_down.out"

# ── test11: CLRL partial-screen clear ────────────────────────────────────
# FIRST (no clear-related keywords) does the default full clear once, then
# SECOND (CLRL(15 20)) must NOT trigger a second full clear — a byte-stream
# capture can't show "this text got cleared" directly (clearing something
# doesn't remove its earlier bytes from the log), so the full-clear *count*
# is what actually distinguishes CLRL's partial clear from a regression
# back to the unconditional full clear (1 vs. 2 — verified both ways while
# writing this).
run_interactive_test \
    "test11: CLRL clears only its row range, not the whole screen" \
    "$TESTDIR/TEST11_CLRL.dspf" "$TESTDIR/TEST11_CLRL.rpgle" \
    '\r' \
    "$EXPECTED/TEST11_CLRL.out" \
    "" "1"

# ── test12: L/T/Z (DATE/TIME/TIMESTAMP) buffer layout ────────────────────
# A date field is a char[len+1] in the generated buffer struct, not a
# fixed-size double — both OpenDSPF's dspf__extractFields/applyFields and
# OpenRPG's own WORKSTN field codegen originally treated any type other than
# 'A'/'B' as numeric, which would desync the buffer walk for every field
# after a date/time/timestamp one. Confirmed for real: before both fixes
# landed, this exact test failed to *compile* (char[11] vs double type
# mismatch in the generated C++) rather than just producing wrong output.
run_interactive_test \
    "test12: date field doesn't corrupt the field after it in the buffer" \
    "$TESTDIR/TEST12_DATETIME2.dspf" "$TESTDIR/TEST12_DATETIME2.rpgle" \
    '2026-01-01\tAFTER\r' \
    "$EXPECTED/TEST12_DATETIME2.out"

# ── test13: ALIAS ─────────────────────────────────────────────────────────
# The RPG driver references the field only as CUSTOMERNAME (the alias) —
# never CRYPTNM (the underlying DDS name) — proving the generated variable
# is actually declared under the alias, not just that the alias parses.
run_interactive_test \
    "test13: ALIAS makes the field addressable by its alias name" \
    "$TESTDIR/TEST13_ALIAS.dspf" "$TESTDIR/TEST13_ALIAS.rpgle" \
    'JohnDoe\r' \
    "$EXPECTED/TEST13_ALIAS.out"

# ── test14: COLHDG ────────────────────────────────────────────────────────
# COLHDG('text') renders as an implicit label one row above its field, at
# the same column, but only where the record has no explicit LITERAL
# already sitting there. NAME1 has empty space above it (row 4, col 10) so
# its heading must be painted; NAME2's heading slot (row 7, col 10) is
# occupied by the 'Real Label' literal, so its heading must be suppressed —
# an author who placed an explicit literal there clearly wants their own
# text, not the fallback. This can't be proven via strip_and_extract's
# RESULT: tags alone (the heading text never reaches DSPLY), so it's
# checked directly against the raw captured screen paint below.
run_interactive_test \
    "test14: COLHDG renders as an implicit label above its field" \
    "$TESTDIR/TEST14_COLHDG.dspf" "$TESTDIR/TEST14_COLHDG.rpgle" \
    '\r' \
    "$EXPECTED/TEST14_COLHDG.out"

printf "%-55s " "test14b: COLHDG suppressed where a LITERAL already sits"
raw14="$TMPDIR/TEST14_COLHDG.raw"
if grep -qF 'Name Hdg' "$raw14" && ! grep -qF 'Should Not Show' "$raw14"; then
    echo -e "${GREEN}PASS${NC}"
    PASS=$((PASS + 1))
else
    echo -e "${RED}FAIL${NC} (heading text mismatch)"
    FAIL=$((FAIL + 1)); FAILURES="$FAILURES\n  test14b: COLHDG suppressed where a LITERAL already sits"
fi

# ── test15: CHANGE / BLANKS ──────────────────────────────────────────────
# Two EXFMT passes of the same record prove both keywords reset fresh each
# pass rather than sticking from a prior one. Pass 1 types into FLDX and
# backspaces FLDQTY's pre-filled "0" blank (an untouched numeric field's
# edit buffer always starts as "0" — see the .rpgle comment — so blanking
# it has to be explicit to test the real "blank" case). Pass 2 leaves FLDX
# untouched and explicitly types "0" into FLDQTY.
#   Pass 1: *IN67 (CHANGE) on, *IN01 (BLANKS) on
#   Pass 2: *IN67 off (nothing keyed this time), *IN01 off (a keyed zero
#           isn't "blank")
run_interactive_test \
    "test15: CHANGE / BLANKS reset fresh each EXFMT pass" \
    "$TESTDIR/TEST15_CHANGE_BLANKS.dspf" "$TESTDIR/TEST15_CHANGE_BLANKS.rpgle" \
    'ABC\t\b\r\t0\r' \
    "$EXPECTED/TEST15_CHANGE_BLANKS.out"

# ── test16: subfile OPTION-field editing + validation + READC ───────────
# dspf__sflExfmt previously had no field-editing at all — only row
# selection via Up/Down + Enter/F-key. This drives the classic per-row
# OPTION pattern end to end: types an invalid option ('9', rejected by
# VALUES('1' '2' ' ') via ERRSFL — the same field-validation path a normal
# record already had, now reachable from a subfile row for the first
# time), corrects it to '2' on row 1 only, then confirms the RPG driver's
# READC loop reads back exactly that one touched row (both the input
# OPTION and the row's own OUTPUT field CUSTNO) and nothing else — rows 2
# and 3 were never touched, so they must never surface via READC.
run_interactive_test \
    "test16: subfile OPTION field — validate, correct, READC" \
    "$TESTDIR/TEST16_SFLOPTION.dspf" "$TESTDIR/TEST16_SFLOPTION.rpgle" \
    '9\r\b2\r' \
    "$EXPECTED/TEST16_SFLOPTION.out"

# ── test17: backward-compat — subfile with no editable fields ───────────
# Same shape as the pre-editing subfile pattern (test02/test04): nothing
# in the control record or the SFL row is input-capable, so
# dspf__sflExfmt's `combined` list is empty and it must fall back to the
# original row-selection-only behavior untouched by the OPTION-field
# rewrite. Only Enter is exercised here — raw arrow-key escape sequences
# don't reliably reach getch() as KEY_UP/KEY_DOWN under this harness's
# piped stdin (confirmed as a pre-existing, unrelated sandbox limitation:
# the identical bytes against TEST08_AUTO, an already-proven code path,
# show the same broken behavior — literal '[' 'B' characters typed instead
# of a key event).
run_interactive_test \
    "test17: subfile with no editable fields renders and exits cleanly" \
    "$TESTDIR/TEST17_SFLSELECT.dspf" "$TESTDIR/TEST17_SFLSELECT.rpgle" \
    '\r' \
    "$EXPECTED/TEST17_SFLSELECT.out"

# ── test18: SFLNXTCHG ─────────────────────────────────────────────────────
# Pass 1: operator types '1' into row 1's OPTION only; the READC loop
# finds it, "detects an error", and UPDATEs it with *IN50 (SFLNXTCHG's
# conditioning indicator) on. Pass 2: operator presses Enter without
# typing anything at all — the READC loop must still find row 1, proving
# SFLNXTCHG resurfaced it purely from the program side. Row 2 was never
# touched by anyone and must never appear in either pass.
run_interactive_test \
    "test18: SFLNXTCHG resurfaces a row via UPDATE, no operator input" \
    "$TESTDIR/TEST18_SFLNXTCHG.dspf" "$TESTDIR/TEST18_SFLNXTCHG.rpgle" \
    '1\r\r' \
    "$EXPECTED/TEST18_SFLNXTCHG.out"

# ── test21: DFTVAL ────────────────────────────────────────────────────────
# Checks the flat RPG variables' values immediately, before ever calling
# EXFMT/WRITE — proving DFTVAL seeded them at declaration time, not at
# some later point. No keystrokes needed: the program never reads input.
run_interactive_test \
    "test21: DFTVAL seeds a field's initial value at declaration" \
    "$TESTDIR/TEST21_DFTVAL.dspf" "$TESTDIR/TEST21_DFTVAL.rpgle" \
    '' \
    "$EXPECTED/TEST21_DFTVAL.out"

# ── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -ne 0 ]; then
    echo -e "${RED}Failed tests:${NC}$FAILURES"
    exit 1
fi
