# OpenDSPF — Feature TODO

Features are grouped by priority for real IBM i RPG migration work.

---

## Critical — breaks real programs

### Subfiles
The most impactful missing feature. Most inquiry and list screens use a subfile
control record (`SFLCTL`) paired with a subfile data record (`SFLDTA`) to render
scrollable tables.

- [ ] `SUBFILE` / `SFLCTL` / `SFLDTA` record type in lexer and parser
- [ ] `SFLPAG` (page size) and `SFLSIZ` (total size) keywords
- [ ] `SFLNXTCHG` — mark changed subfile records
- [ ] AST nodes for subfile record pairs
- [ ] Codegen: emit subfile metadata to `.dspfd` JSON
- [ ] Runtime: render subfile as a scrollable ncurses table (Page Up / Page Down)
- [ ] Buffer: generate array-of-struct in `_dspf.h` for subfile rows

### Conditioning indicators
Fields and records conditioned on `*IN01`–`*IN99` are silently ignored today;
the field always displays regardless of indicator state.

- [ ] `COND(indicator field)` keyword in lexer / parser
- [ ] Store indicator conditions on fields and records in AST / JSON
- [ ] Runtime: skip rendering fields whose condition indicator is off
- [ ] Runtime: write-protect fields when condition indicator is on

### EDTCDE / EDTWRD (numeric formatting)
Edit codes and edit words are parsed but never applied. Numeric output fields
display raw digits with no commas, decimal points, sign, or date separators.

- [ ] Parse `EDTCDE(n)` arguments into structured JSON (not opaque string)
- [ ] Parse `EDTWRD('mask')` into structured JSON
- [ ] Runtime: apply edit code formatting when rendering output/both numeric fields
  - `1` — comma separator, no sign
  - `2` — comma separator, sign (CR)
  - `3` / `4` — no separator variants
  - `A`–`D` — zero-suppress variants
  - `J`–`Q` — date/time edit codes
  - `Y` — date with separators
  - `Z` — remove leading zeros and sign

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
