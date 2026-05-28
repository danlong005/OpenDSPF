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
- [ ] Right-align numeric field values (`S`, `P`, `B`, `F` types) on output
- [ ] Zero-pad to field length and decimal places
- [ ] Show decimal point at correct position

### Auto-advance on field fill
- [ ] Cursor automatically moves to next field when current field is full
- [ ] `AUTO` keyword (auto-advance attribute)

### REFFLD — reference field definitions
- [ ] Parse `REFFLD(fieldname [recordname] [*FILE filename])` in DDS reader
- [ ] Look up referenced field length, type, and edit code
- [ ] Apply inherited attributes to the referencing field

### PROTECT — conditional write-protect
- [ ] `PROTECT` keyword: write-protect all input/both fields based on indicator
- [ ] Runtime: skip editable fields when record-level PROTECT is active

### Error indicators and highlighting
- [ ] `*IN99` (general error indicator) — highlight erroneous field in reverse/red
- [ ] `ERRSFL` — route error messages to subfile
- [ ] Field-level error indicator: highlight specific field when its indicator is on

---

## Runtime behaviour gaps

- [ ] `KEY_HOME` / `KEY_END` — jump to first / last field
- [ ] `KEY_UP` / `KEY_DOWN` — move between fields by row
- [ ] `KEY_PPAGE` / `KEY_NPAGE` — Page Up / Page Down (needed for subfiles)
- [ ] `CLRL` — clear remainder of screen before writing
- [ ] `OVERLAY` — do not clear screen before writing (overlay on prior record)
- [ ] `ALARM` — ring terminal bell on EXFMT
- [ ] `NOINPUT` — disable all input fields for this EXFMT
- [ ] `NOCLEAR` — retain prior screen content

---

## DDS A-spec reader gaps

- [ ] `L`, `T`, `Z` date/time/timestamp field types (columns 34–35)
- [ ] `COLHDG('text')` — column heading (use as field label when no LITERAL)
- [ ] `ALIAS(name)` — alternate field name for generated struct member
- [ ] `CHCCTL` — choice control field
- [ ] `VALUES(...)` — allowed value list (validation)
- [ ] `RANGE(lo hi)` — range validation
- [ ] `COMP(op value)` — comparison validation
- [ ] `BLANKS` / `CHANGE` — condition keywords

---

## Advanced / low priority

### Window and overlay records
- [ ] `WINDOW(row col height width)` keyword
- [ ] Runtime: render record in a bordered ncurses subwindow at specified position
- [ ] `OVERLAY` — write record without clearing the screen first

### Field validation
- [ ] `VALUES(v1 v2 ...)` — reject input not in list
- [ ] `RANGE(lo hi)` — reject input outside range
- [ ] `COMP(op value)` — comparison check on submit
- [ ] Display inline error on validation failure before returning to caller

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

- [ ] Proper error reporting with source line numbers (currently silent on unknown keywords)
- [ ] Warning on unrecognised keywords rather than silent ignore
- [ ] Validate `SFLPAG` ≤ `SFLSIZ`
- [ ] Validate field row/col fits within declared `SCREEN SIZE`
- [ ] Cross-record field reference checking for `REFFLD`
