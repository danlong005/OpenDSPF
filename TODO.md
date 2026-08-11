# OpenDSPF — Feature TODO

Features are grouped by priority for real IBM i RPG migration work.

---

## Critical — breaks real programs

### Subfiles ✅
- [x] `SUBFILE` / `SFLCTL` record type in lexer, parser, AST
- [x] `SFLPAG` / `SFLSIZ` keywords (free-format and DDS A-spec)
- [x] Codegen: emit `"type"`, `"sfl"`, `"sflpag"`, `"sflsiz"` to `.dspfd` JSON
- [x] Runtime: `dspf_write` SFL record appends row to subfile store
- [x] Runtime: `dspf_write` SFLCTL clears the associated subfile
- [x] Runtime: `dspf_exfmt` SFLCTL renders scrollable table (Up/Down/PgUp/PgDn)
- [x] Runtime: Enter / F-key exits with selected RRN written to SFLRCDNBR field
- [ ] `SFLNXTCHG` — mark changed subfile records (low priority)

### Conditioning indicators ✅
- [x] `COND(*INxx)` / `COND(N*INxx)` stored on fields and literals in AST / JSON
- [x] DDS A-spec option indicators (cols 7–9) parsed → `COND` keyword
- [x] `dspf_set_indicators(bool*, int)` API — caller passes indicator array before each I/O op
- [x] OpenRPG codegen emits `dspf_set_indicators(rpg_indicators, 100)` before EXFMT/WRITE/READ
- [x] Runtime: conditioned fields and literals skipped when indicator is off

### EDTCDE / EDTWRD (numeric formatting) ✅
- [x] Runtime: `dspf__applyEditCode` — codes 1–4, A–D, J–Q, Y, Z
- [x] Runtime: `dspf__applyEditWord` — digit-slot mask formatting
- [x] Applied automatically during screen rendering for numeric output/both fields

---

## Important — common in real DDS

### Numeric field display
- [x] Right-align numeric field values (`S`, `P`, `B`, `F` types) on output
- [x] Zero-pad to declared field length (no EDTCDE/EDTWRD) — IBM i style `001234.56`
- [x] Decimal point at correct position when no edit code is applied

### Auto-advance on field fill ✅
- [x] Cursor automatically moves to next field when current field is full
- [x] `AUTO` keyword — advance is now conditional on the keyword being present
      (was previously unconditional for every field regardless of AUTO)

### REFFLD — reference field definitions
- (not supported — skipped by design)

### PROTECT — conditional write-protect ✅
- [x] `PROTECT` keyword: write-protect all input/both fields (record-level)
- [x] `PROTECT(*INxx)` — indicator-conditioned write-protect
- [x] Runtime: editable field list suppressed when PROTECT is active

### Error indicators and highlighting ✅
- [x] Field-level conditional DSPATR via option indicators — same field appears twice with mutually exclusive COND; duplicate buffer-slot sharing in runtime; header deduplication in codegen
- [x] `ERRSFL` / `SFLMSGRCD(nn)` — validation errors accumulate into a
      scrollable message area starting at row nn, instead of overwriting a
      single status line each time. Not a full IBM i message-file/program
      message queue implementation (OpenDSPF has neither) — routes the
      validation-error text dspf__validateField already produces, same
      observable multi-message-list behavior. Still only enforced in the
      main input loop (dspf__inputLoop), not the SFLCTL control-record loop
      (dspf__sflExfmt) — see the pre-existing note under Field validation
      below; that's a separate gap (validation not enforced there at all).

---

## Runtime behaviour gaps ✅

- [x] `KEY_HOME` / `KEY_END` — jump to first / last field
- [x] `KEY_UP` / `KEY_DOWN` — move between fields (same as Tab/Shift-Tab)
- [x] `OVERLAY` — do not clear screen before writing (overlay on prior record)
- [x] `ALARM` — ring terminal bell on EXFMT
- [x] `NOINPUT` — disable all input fields for this EXFMT
- [x] `NOCLEAR` — retain prior screen content
- [x] `CLRL(begline [endline])` — clears only that row range before writing
      (endline omitted = to the bottom), instead of the default full-screen
      clear. Takes effect only when neither OVERLAY nor NOCLEAR is present.
- [x] `KEY_PPAGE` / `KEY_NPAGE` — Page Up / Page Down as exit keys on
      non-subfile records (subfiles already handled scrolling). Fixed-format
      `ROLLUP(ind)`/`ROLLDOWN(ind)` map to `PAGEDOWN`/`PAGEUP` respectively —
      real DDS naming is inverted from the physical key (ROLLUP = content
      rolls up = Page Down).

---

## DDS A-spec reader gaps

- [x] `L`, `T`, `Z` date/time/timestamp field types (columns 34–35)
- [x] `COLHDG('text')` — column heading (use as field label when no LITERAL)
- [x] `ALIAS(name)` — alternate field name RPG source can reference the field
      by; the generated struct member itself stays the DDS name (matches
      real IBM i semantics — ALIAS is an HLL-facing alternate name, not a
      record-layout rename)
- [ ] `CHCCTL` — choice control field
- [x] `VALUES(...)` — allowed value list (validation)
- [x] `RANGE(lo hi)` — range validation
- [x] `COMP(op value)` — comparison validation
- [ ] `BLANKS` / `CHANGE` — condition keywords

---

## Advanced / low priority

### Window and overlay records
- [x] `WINDOW(row col height width)` keyword — parsed by compiler, emitted to `.dspfd` JSON
- [x] Runtime: render record in a bordered ncurses subwindow at specified position
- [x] `OVERLAY` — write record without clearing the screen first (see Runtime behaviour gaps above)

### Field validation ✅
- [x] `VALUES(v1 v2 ...)` — reject input not in list
- [x] `RANGE(lo hi)` — reject input outside range
- [x] `COMP(op value)` — comparison check on submit
- [x] Display inline error on validation failure before returning to caller — status-line message on the terminal's extra row (`LINES > 24`), cursor returns to the offending field; not enforced in the subfile control-record loop (`dspf__sflExfmt`), only the main `dspf__inputLoop`

### Miscellaneous DDS keywords
- [ ] `PULLDOWN` / `PSHBTN` — menu bar and push-button widgets
- [ ] `CMDKEY(text ind)` — command key with description
- [ ] `HLPRCD(record file)` — link F1 to a help record
- [ ] `SFLMSG` / `SFLMSGID` — subfile message line
- [ ] `MSGCON` — message constant (looked up from message file)
- [ ] `DFTVAL(value)` — default field value
- [ ] `WRDWRAP` — word-wrap long text fields
- [ ] `INDTXT(ind 'text')` — indicator text descriptions

### Free-format DSPF syntax additions
- [ ] `COLOR(...)` on `LITERAL` lines
- [ ] `DSPATR(...)` on `LITERAL` lines
- [ ] Conditioning indicator syntax on `FIELD` and `LITERAL` lines (`COND(*IN03)`)
- [ ] `SUBFILE` / `SFLCTL` block syntax

---

## Compiler infrastructure

- [x] Warning on unrecognized record-level DDS keyword, with file:line — the fixed-format reader
      used to drop anything outside a hardcoded allowlist with zero trace (how WINDOW/WDWBORDER
      support went missing from this reader for 2.5 months, unnoticed). Field- and literal-level
      keywords are intentionally left unwarned — both formats store them generically for the
      runtime to act on later, so an unrecognized one isn't a bug, just not wired up yet.
- [ ] Validate `SFLPAG` ≤ `SFLSIZ`
- [ ] Validate field row/col fits within declared `SCREEN SIZE`
- [ ] Cross-record field reference checking for `REFFLD`
