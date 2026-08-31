# OpenDSPF — Feature TODO

Features are grouped by priority for real IBM i RPG migration work.

---

## Critical — breaks real programs

### Subfiles — mostly ✅, see the control keywords below
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

### Subfile control keywords — SFLDSP / SFLDSPCTL / SFLCLR / SFLEND ✅ (2026-08-31)

These decide whether a subfile is displayed, whether its control record is
displayed, and whether writing the control record clears it.  Real DDS
conditions them from the option-indicator columns, and essentially every
subfile program uses them; none were recognized, so all three behaviours were
unconditional.

The one that broke correct programs is `SFLCLR`.  `dspf_write` cleared the
subfile on *every* control-record write, but the ordinary load-then-display
idiom writes it twice — once with SFLCLR's indicator on to clear, then again
after loading rows with it off.  That second write wiped the rows.

**Compatibility rule: presence decides.**  Declare one of these and it is
honoured exactly, indicator condition included; omit it and the old
unconditional behaviour stands.  Display files written against this compiler
say none of them and keep working, while real DDS behaves the way its author
meant.  A divergence from IBM, where the keywords are required, and a
deliberate one.

Two things had to exist first:

- **Record-level keywords could not be conditioned from fixed-format DDS at
  all.**  The reader warned that an option indicator on a keyword line was
  dropped.  A bare keyword now takes the condition into its own text
  (`SFLCLR` -> `SFLCLR(*IN90)`), which is the shape `PROTECT(*INxx)` and
  `SFLNXTCHG(*INxx)` already used.  A keyword that already has parameters has
  nowhere to put it and still says so.
- **`dspf__hasRecKw` is a prefix test**, so it reports `SFLDSPCTL` as
  `SFLDSP`.  The new `dspf__recKwActive`/`dspf__hasRecKwExact` require an
  exact name or a following `(`.  `dspf__isProtected` and
  `dspf__sflNxtChgActive` were two copies of the same indicator parser and are
  now one line each.

`SFLEND` renders the `*MORE` wording (`More...`/`Bottom`) for every parameter
form, since `*SCRBAR` has no scroll bar to draw here and `*PLUS` is a 5250
convention.

Still absent, and unranked: `SFLINZ`, `SFLRNA`, `SFLDROP`, `SFLFOLD`,
`SFLMODE`, `SFLLIN`, `SFLCSRRRN`, `SFLSCROLL`, `SFLROLVAL`, `SFLENTER`,
`SFLPGMQ`, `SFLRTNSEL`, `SFLSNGCHC`, `SFLMLTCHC`.

**Found while testing this, and worse than the bug it hid.** `rpgc` compiles
the interactive drivers against **its own** runtime directory, which holds a
*mirror* of `runtime/rpg_dspf_runtime.h` — byte-identical at HEAD, and updated
by hand.  So a runtime change in this repo is invisible to this repo's own
interactive tests until the mirror is copied across.  All four keywords were
implemented, the whole suite passed, and none of the new runtime code had ever
executed.  `tests/run_interactive.sh` now diffs the two and refuses to run
when they differ, printing the `cp` that fixes it.  It does not sync
automatically: someone may be editing the display runtime from the OpenRPG
side, and clobbering that silently would be worse than stopping.

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

### REF / REFFLD — reference field definitions

**DECISION (2026-08-31): not supported. A boundary, not a gap.**

`REF(file)` and `REFFLD(...)` let a field take its length and data type from
a field in another file, so a display file need not restate what the database
already declares.  The reference names an IBM i database `*FILE` object and is
resolved by reading the definitions out of the object itself.  `dspfc`
compiles one source file standalone — no database, no catalog, no IBM i — so
there is nothing for the reference to denote.  Same shape as OpenRPG's
decision that database record formats are a platform divergence: the concept
has no referent off the platform, and honouring it would mean inventing one.

An `R` in position 29 is now a hard error naming the keyword.  That is the
change worth having: it used to fall through to the constant branch and drop
the field entirely, so a reference-defined field vanished without a word.
Refusing beats guessing a length, which puts the field on screen at the wrong
width.

*Consequence, stated plainly:* real shop DDS leans on `REF` heavily, and such
a file will not compile unmodified — each reference-defined field needs its
length and data type written out.  `tests/sample.dspf` is the measure of that
cost: 15 of its 19 fields are reference-defined.  It is kept, and pinned as a
diagnostic test, precisely so the cost stays visible rather than becoming
folklore.

Unrelated to this decision, and now built: the file-level keyword area is
read rather than skipped — see below.

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

### File-level keyword area ✅ (2026-08-31)

Keyword lines before the first `R` record format are the file-level keyword
area.  Every one of them was skipped outright — the reader bailed on
`file.records.empty()` — so `INDARA`, `REF`, `PRINT` and `CHGINPDFT` all
vanished without a word.  The area is now parsed, `INDARA` is honoured, and
anything else is reported instead of dropped, which is what makes the
remaining file-level work discoverable rather than folklore.

- [x] `INDARA` — recorded on `DspfFile` and emitted as `"indara": true`.
      It declares that indicators travel in a separate indicator area rather
      than inside the record buffer, which is unconditionally what this
      toolchain already does: the runtime keeps its own `g_dspf_indicators`
      array, OpenRPG's codegen passes the whole array through
      `dspf_set_indicators()` before every I/O, and the record buffer is a
      generated struct of named fields with no indicator bytes in it.  So the
      keyword agrees with the implementation and is a declaration, not a
      switch.  Its *absence* is deliberately not diagnosed: the alternative
      layout is a 5250 data-stream convention and nothing here emits a 5250
      data stream, so there is nothing a warning could tell anyone to do.
- [ ] `PRINT` — **DECISION (2026-08-31): not supported.**  It enables the
      Print key, so the operator can print the current screen image:
      `PRINT` spools it to `QSYSPRT`, `PRINT(printer-file)` to a named
      printer file.  Neither has a referent here — this toolchain has no
      printer output at all, for any file type, so honouring it would mean
      inventing a screen-dump convention rather than implementing DDS.  The
      third form, `PRINT(response-indicator)`, hands the Print key to the
      program instead of printing, and *is* mechanically identical to `CFnn`
      — but the keyboards this runs on have no Print key to bind, so it would
      need an invented binding too.  Ignored with a warning rather than
      refused: an unhonoured Print key is a missing convenience, not wrong
      output, and erroring would reject real DDS over it.
- [ ] `CHGINPDFT` — **undecided.**  "Change input default": it alters the
      defaults for *input-capable* fields in scope (file, record or field
      level).  Bare, it removes IBM i's default underline on input fields;
      with parameters it sets display attributes (`HI`/`BL`/`CS`/`ND`/`PC`/
      `PR`/`RI`/`UL`) and/or `LC` (allow lowercase) and/or `FE` (field exit
      required).  `tests/sample.dspf` carries `CHGINPDFT(CS)` — every input
      field gets column separators.

      Unlike `PRINT` this has a plain referent: it is a default for
      attributes the field level already carries.  **But see the attribute
      gap below — implementing it first would faithfully propagate an
      attribute that then does nothing.**  The useful order is attributes
      first, defaulting second.

**Found while reading this — the runtime implements four DSPATR attributes,
not eight.** `dspf__fieldAttrs` maps `HI`/`BL`/`RI`/`UL` onto ncurses
attributes and nothing else, so `DSPATR(CS)`, `(ND)`, `(PR)` and `(PC)` parse,
reach the descriptor, and are then silently skipped at render time —
`tests/sample.dspf`'s `DSPATR(CS)` and `DSPATR(PR)` already draw as plain text
today.  Of the four, `ND` (nondisplay) and `PR` (protect) are worth the most:
they change *behaviour*, not just appearance, and `PR` overlaps the
record-level `PROTECT` keyword that is already implemented.  This is the
prerequisite for a useful `CHGINPDFT`.
- [x] File-level `CAnn`/`CFnn` (and `ROLLUP`/`ROLLDOWN`, which reach the same
      `DspfKey` through the same two-function test — splitting them would have
      been an arbitrary boundary).  They apply to every record format in the
      file.  A record declaring the same key names its own indicator for it
      and wins, matching DDS, where a record-level keyword overrides the
      file-level one of the same name.  The merge runs after the whole source
      is read, not when each record is pushed: a record's own keys arrive on
      lines *following* its `R` line, so at push time it does not yet know
      what it has spoken for.  Tests 25 (descriptor), 25a/25b (interactive).

**Found while testing this — not fixed, and not caused by it.** The runtime
exits on *any* function key: `dspf__inputLoop` and `dspf__sflExfmt` both look
the pressed key up in the record's `keys[]` and, failing to find it, `return
fnum` — the key's own number as the indicator.  On real IBM i a function key
the record format does not declare is invalid; the workstation rejects it and
the keyboard locks.  So an undeclared F6 here quietly sets `*IN06` and exits,
where a real 5250 would refuse.

This matters beyond fidelity because it silently weakens tests.  Test 25a's
first version had the file-level key as `CA12(12)`, and *IN12 gets set either
way — by inheritance, or by the fallback — so it passed with the merge
disabled.  It now uses `CA12(45)`, an indicator deliberately different from
the key number, and the driver reports `*IN12` as a distinct
`F12-UNDECLARED` result rather than folding it into the failure branch.
**Any test asserting on a function key's indicator has to keep the two
numbers different, or it proves nothing.**

Tests 24 (descriptor) and 24/24b (interactive).  Test 24 is also the first
interactive test whose display file is fixed-format DDS: every other one
compiles free-format source, so the DDS reader's output had never been
executed, only diffed as JSON.  It sets `*IN50` on and checks that the
conditioned literal for 50 renders and the `N50` one does not — asserted
against the raw terminal capture, since no `DSPLY` output can carry it.  That
assertion earned itself immediately: the first draft of the fixture put the
indicator one column right of positions 9-10, nothing was conditioned at all,
and both literals rendered.

### Column layout and continuation ✅ (2026-08-31)

Three defects found by running a real shop display file (`tests/sample.dspf`,
a `CUSMNT`-style customer-maintenance screen) through `dspfc`.  It "compiled"
— exit 0 — while silently discarding 28 keywords and 15 fields.

- [x] **Positions 17-18 are validated, not guessed at.** Position 17 must be
      `R` or blank and position 18 must be blank, so a misaligned line is
      refused instead of quietly becoming a different kind of entry — which is
      how the field-name column bug (fixed separately in 2a8026a: the name was
      read from 17-26 instead of 19-28, silently truncating anything past
      eight characters) stayed invisible for so long.  Position 29 is also
      read as its own entry now, the Reference column, rather than as the
      first digit of Length at 30-34.
- [x] **Keyword lines were always record-level.** A line with no name and no
      position continues the keyword list of the record's last field or
      constant; only before the first one is it record-level.  Every one of
      them went to the record, where `DSPATR`/`EDTCDE`/`CHECK` are not
      record-level keywords and were reported as unrecognized and dropped —
      21 `DSPATR`, 4 `EDTCDE`, 2 `ERRMSG`, 1 `CHECK` in the sample alone.
      The two copies of the record-keyword dispatch (one for the `R` line, one
      for keyword lines) have been folded into `applyRecordKeyword()`; they had
      already drifted apart, with `TEXT()` honoured on the `R` line and
      reported as unrecognized on a following line.
- [x] **No `+`/`-` entry continuation.** A `+` or `-` in the last non-blank
      position of the functions area continues the entry on the next
      specification line (`+` resumes at its first non-blank position, `-` at
      position 45 exactly).  Without it, `ERRMSG('CUSTOMER ALREADY ON +` /
      `FILE' 51)` parsed as the two garbage tokens `FILE'` and `51)`.  Text
      before the continuation character is kept verbatim, trailing blanks
      included — that is what makes the join read `ALREADY ON FILE` rather
      than `ALREADY ONFILE`.

Two more silent drops became diagnostics rather than nothing:
a positioned line yielding no quoted text (DDS's `DATE`/`TIME`/`USER`/
`SYSNAME`/`MSGCON` constants — none supported) now warns instead of vanishing,
and an option indicator on a keyword line warns that it conditions those
keywords individually, which this compiler models per entry, not per keyword.

The test fixtures were themselves written in the old columns and were moved by
a throwaway script, not by hand.  It is deliberately not kept: the reader now
*enforces* what it was migrating toward, so a misaligned line is caught at
compile time with a message naming the right columns, and re-running the script
over `tests/*.dspf` would silently "fix" test23b, whose whole purpose is to be
misaligned.  Two hazards it did surface are worth remembering.  Position 6
means nothing in a free-format source, so a prose comment whose sixth character
happens to be `a` looks exactly like an A-spec — an unguarded first run
shredded four free-format fixtures.  And a blanket rewrite cannot assume the
old layout: applied to a line already in standard columns it re-slices a
ten-character name out of the nine-column old window and drops the last
character (`SFLRCDNBR` -> `SFLRCDNB`).  Tests 23 / 23b / 23c.

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
- [ ] `PULLDOWN` / `PSHBTN` — menu bar and push-button widgets.
      **Deferred**: same reason as `CHCCTL` — real IBM i semantics tie
      these to graphical-workstation widget rendering (pull-down menus,
      multi-choice push-button fields), infrastructure this ncurses-based
      compiler doesn't implement at all.
- [ ] ~~`CMDKEY(text ind)` — command key with description~~ — **dropped**:
      couldn't confirm this exists as a real DDS keyword under this name/
      shape; likely an inaccurate leftover (possibly conflated with
      `CFxx(ind)`/`CAxx(ind)`, which this compiler already implements via
      `KEY Fn INDICATOR(nn)`).
- [ ] `HLPRCD(record file)` — link F1 to a help record. **Deferred**: real
      semantics live in DDS's separate Help-specification section (`H` in
      column 17), an entirely different specification type this
      compiler's parser doesn't handle at all — a bigger addition than
      one keyword.
- [ ] `SFLMSG` / `SFLMSGID` — subfile message line. **Deferred**: needs a
      real IBM i message-file mechanism (program message queue, severity
      levels, replacement variables) as a prerequisite — this project has
      never built one (same gap noted under `ERRSFL`, which approximates
      message *display* without a real message file underneath).
- [ ] `MSGCON` — message constant (looked up from message file).
      **Deferred**: same message-file prerequisite as `SFLMSG`/`SFLMSGID`.
- [x] `DFTVAL('text')` — default field value. Implemented purely at
      OpenRPG codegen time: the flat RPG variable for an OUTPUT/BOTH
      field is initialized to `DFTVAL`'s value instead of blank/zero at
      declaration, matching real semantics (the field's displayed content
      before the program ever sets it) for free — no runtime changes
      needed, and it works identically for a subfile row's fields too
      (whatever the flat var holds at `WRITE` time becomes the row's
      stored value).
- [ ] `WRDWRAP` — word-wrap long text fields. **Deferred**: genuinely
      requires `CNTFLD` (Continued Field — splitting one long field
      across multiple physical display lines) as a prerequisite; without
      it there's no "continuation" to word-wrap. Not implemented.
- [x] `INDTXT(ind 'text')` — indicator text description. Purely compile-
      time documentation even on real IBM i (no runtime effect at all) —
      field-level already worked via generic keyword passthrough; added
      record-level grammar (bare field-level form already covered
      `*IN50`-style indicator refs, matching this dialect's convention).

### Free-format DSPF syntax additions
- [x] `COLOR(...)` / `DSPATR(...)` on `LITERAL` lines — these already
      *parsed* correctly in both formats (`LITERAL` reuses the same
      generic keyword grammar as `FIELD` free-format-side; fixed-format's
      literal reader has never had an allowlist restriction either). The
      actual gap was purely in `dspf__renderScreen`'s literal-rendering
      loop, which called `mvwprintw` directly with no color/attribute
      handling at all — `dspf__colorPair`/`dspf__fieldAttrs` already
      existed and worked unmodified once pointed at a literal's JSON
      (same "keywords" array shape as a field).
- [x] Conditioning indicator syntax on `FIELD` and `LITERAL` lines (`COND(*IN03)`) — already implemented and tested (`test03_cond.dspf`); this line was just never checked off
- [x] `SUBFILE` / `SFLCTL` block syntax — already implemented and tested (`test02_subfile.dspf`); same stale-checkbox situation

---

## Compiler infrastructure

- [x] Warning on unrecognized record-level DDS keyword, with file:line — the fixed-format reader
      used to drop anything outside a hardcoded allowlist with zero trace (how WINDOW/WDWBORDER
      support went missing from this reader for 2.5 months, unnoticed). Field- and literal-level
      keywords are intentionally left unwarned — both formats store them generically for the
      runtime to act on later, so an unrecognized one isn't a bug, just not wired up yet.
- [x] Validate `SFLPAG` ≤ `SFLSIZ` — hard error (not a warning): a
      structurally broken spec, unlike an unrecognized keyword. Runs on
      the fully-parsed, format-agnostic AST in `main.cpp`, so free- and
      fixed-format source both get it from the same code.
- [x] Validate field/literal row/col fits within declared `SCREEN SIZE` —
      a warning, matching unrecognized-keyword severity (cosmetic, not
      structural; a developer should still be able to compile and iterate
      with a temporarily-misplaced field). `HIDDEN` fields are exempt —
      never rendered, so their position is irrelevant.
- [x] ~~Cross-record field reference checking for `REFFLD`~~ — moot:
      `REFFLD` itself is "not supported — skipped by design" (see
      "REFFLD — reference field definitions" above), so there's nothing
      to check references for.

### CI actually runs the interactive tests ✅ (2026-08-31)

The 22 interactive tests ran on nobody's machine but this one until now. CI
reported `SKIP: rpgc not found` on every runner, because the harness looked
for `../OpenRPG/rpgc` and this repo is checked out as `OpenDSPF/`. Fixing
that lookup turned the skip into a run, and the run failed everywhere at
once.

The cause was not a missing dependency. `libncurses-dev` was already
installed on the Ubuntu runners. `rpgc` was building its command as
`... -lncurses -o prog prog.cpp`, and GNU ld resolves left to right — under
`--as-needed` it discarded ncurses before reading the source that needed it.
Apple's linker is order-independent, so a Mac never saw it. The same bug
applied to `-lodbc`; `tests/run_tests.sh` had been sidestepping it for SQL
tests by compiling those by hand with the flags appended last, with a
comment explaining the ordering, but `rpgc` itself was never given the same
treatment. Fixed in OpenRPG's `src/main.cpp`.

Linux x86_64, Linux ARM64 and macOS now run all 22. Windows sets
`SKIP_DSPF_RUNTIME=1`: MSYS2's pdcurses is not the wincon build the
installer ships, it hides `curses.h` under `include/pdcurses/`, and its
default wingui port paints a window rather than stdout, so the captures
these tests diff would be empty even once it linked. Windows display-file
behaviour is untested, and the workflows say so.
