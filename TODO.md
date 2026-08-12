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
- [x] Field editing in the SFLCTL control-record loop (`dspf__sflExfmt`) —
      previously there was none at all: only Up/Down/PgUp/PgDn row
      selection and Enter/F-key exit, no typing anywhere. Now supports
      both the control record's own input-capable fields (e.g. a search
      box) and per-row input fields (the classic OPTION-column pattern —
      type 1/2/4 next to a row), navigated via Tab/Shift-Tab across a
      combined list (control fields, then each visible row's fields).
      Since every subfile row shares the same field template, either
      every row has the same editable fields or none do.
- [x] Field validation (`VALUES`/`RANGE`/`COMP`) and `ERRSFL` now enforced
      in `dspf__sflExfmt`, not just the main `dspf__inputLoop` — this was
      the actual gap tracked under "Field validation" below. Fixing it
      surfaced a real pre-existing bug: `VALUES` comparison trimmed the
      submitted value but not the allowed-list tokens, so an explicit
      blank-allowed token (`VALUES('1' '2' ' ')` — needed since most
      subfile rows are legitimately left untouched) could never match.
- [x] `READC` (Read Changed) opcode (OpenRPG lexer/parser/codegen +
      `dspf_readc()` runtime) — pops each subfile row the operator typed
      into, ascending RRN, into the SFL record's own buffer, mirroring
      real IBM i's per-row-OPTION processing loop. Unlike a normal
      EXFMT/READ copy-back (input/both fields only), READC copies every
      non-hidden field, since a row's OUTPUT fields (e.g. a key like
      CUSTNO) are how the program identifies *which* row was touched.
      `%EOF(recordname)` reports when there are none left.
- [x] `SFLNXTCHG` — record-level keyword on the SFL record (bare, or
      conditioned by an option indicator: `SFLNXTCHG(*INxx)`). Real
      semantics needed a prerequisite this compiler didn't have at all:
      `UPDATE recordname` for a WORKSTN subfile row — added
      `dspf_update()`, which rewrites whatever row `READC` most recently
      returned (mirrors real DDS's implicit "current record" pointer;
      `UPDATE` takes no RRN itself). When `SFLNXTCHG` is in effect for
      that `UPDATE` call, the row is force-remarked as changed even
      though the operator never touched it — the real-world "program
      detected an error, reject it and make the operator look again"
      loop. Staged separately from the operator-typed changed-row queue
      and merged in only at the *next* redisplay, matching real timing
      (an `UPDATE` mid-`READC`-loop must not resurface in that same loop
      — it becomes visible starting the next `EXFMT`, not immediately).
- [x] `HIDDEN` (`H`) usage fields now carry a real value through the
      buffer end-to-end — previously they were skipped at three separate
      layers that all had to agree: the runtime's own
      `dspf__extractFields`/`dspf__applyFields` never read/wrote an H
      field's actual bytes (only advanced the pointer), OpenDSPF's
      `_dspf.h` struct generation gave them no member at all, and
      OpenRPG's codegen skipped them at DCL-F WORKSTN declaration and
      every EXFMT/READ/WRITE/READC copy loop. Real DDS `H` only means
      "not rendered," not "no data" — the classic `SFLRCDNBR HIDDEN`
      pattern needs the program to read it back after EXFMT to know which
      row was selected, which now works (test17).

      Fixing it surfaced a second, unrelated, wider-reaching bug: OpenDSPF's
      `cppFieldType()` special-cased zoned/packed fields with **zero**
      decimal places as C++ `long`, while both OpenRPG's codegen and the
      runtime's own buffer-walking code always assume `double` for those
      types. The mismatch silently type-punned a double-encoded buffer
      slot as a 64-bit integer wherever generated C++ read it directly —
      not HIDDEN-specific; it affected *any* whole-number zoned/packed
      WORKSTN field. Never caught before because no existing test read
      such a field's value back (only its presence or an indicator it
      set). Fixed by always using `double`, matching the rest of the
      codebase's existing assumption; regenerated 5 golden `_dspf.h`
      files whose struct layout silently changed as a result.

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
- [ ] `CHCCTL` — choice control field. **Deferred**: real IBM i semantics tie
      this to `CHOICE`/`PSHBTNCHC` selection-field keywords (GUI-style
      list/radio controls for 5250 graphical workstations), none of which
      this ncurses/terminal-based compiler implements. It already parses
      without error (generic keyword passthrough) but has no runtime
      effect. Giving it real behavior means building a selection-field
      subsystem first — out of scope for this tier; revisit if/when CHOICE
      fields are undertaken as their own feature.
- [x] `VALUES(...)` — allowed value list (validation)
- [x] `RANGE(lo hi)` — range validation
- [x] `COMP(op value)` — comparison validation
- [x] `BLANKS(ind ['text'])` / `CHANGE(ind ['text'])` — condition keywords.
      BLANKS: field-level, numeric input fields — sets `ind` on when the
      field is left/keyed blank (distinguishing that from a real zero).
      CHANGE: record- or field-level — sets `ind` on when the operator
      keys into the field (or any input-capable field, at record level)
      during that screen's input cycle, mirroring real MDT semantics
      (keying the same value back in still counts; it resets fresh each
      EXFMT since this runtime always redraws rather than modeling
      PUTRETAIN).

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
- [x] Display inline error on validation failure before returning to caller — status-line message on the terminal's extra row (`LINES > 24`), cursor returns to the offending field. Now enforced in the subfile control-record loop (`dspf__sflExfmt`) too, not just the main `dspf__inputLoop` — see "Subfiles" above.

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
- [x] Conditioning indicator syntax on `FIELD` and `LITERAL` lines (`COND(*IN03)`) — already implemented and tested (`test03_cond.dspf`); this line was just never checked off
- [x] `SUBFILE` / `SFLCTL` block syntax — already implemented and tested (`test02_subfile.dspf`); same stale-checkbox situation

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
