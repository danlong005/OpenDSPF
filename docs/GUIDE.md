# OpenDSPF User's Guide

OpenDSPF compiles IBM i display file source into portable artifacts that run on macOS, Linux, or Windows — no IBM i required. Both source formats use the `.dspf` extension: a `**FREE` header at the top selects free-format syntax; files without it are interpreted as fixed-format (IBM i DDS A-spec column layout). OpenDSPF pairs with [OpenRPG](https://github.com/danlong005/OpenRPG) to run RPG programs that use `DCL-F ... WORKSTN` display files.

---

## Table of Contents

1. [Building from Source](#building-from-source)
2. [CLI Reference](#cli-reference)
3. [Free-Format Syntax](#free-format-syntax)
4. [Fixed-Format Syntax](#fixed-format-syntax)
5. [Record Types](#record-types)
6. [Fields](#fields)
7. [Literals](#literals)
8. [Function Keys](#function-keys)
9. [Subfiles](#subfiles)
10. [Conditioning Indicators](#conditioning-indicators)
11. [Numeric Formatting — EDTCDE and EDTWRD](#numeric-formatting--edtcde-and-edtwrd)
12. [Generated Outputs](#generated-outputs)
13. [Runtime API](#runtime-api)
14. [Integration with OpenRPG](#integration-with-openrpg)
15. [Testing](#testing)

---

## Building from Source

**Prerequisites:** C++17 compiler (clang++ or g++), Flex, Bison.

```bash
# macOS
brew install flex bison

# Linux (Debian/Ubuntu)
sudo apt install flex bison g++

# Windows — MSYS2 MINGW64 shell
pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-flex mingw-w64-x86_64-bison make
```

```bash
git clone https://github.com/danlong005/OpenDSPF.git
cd OpenDSPF
make
sudo make install        # installs to /usr/local
```

To install to a different prefix:

```bash
make install PREFIX=~/.local
```

This installs:
- `dspfc` binary to `$PREFIX/bin/`
- `rpg_dspf_runtime.h` to `$PREFIX/share/rpgc/runtime/`

---

## CLI Reference

```
dspfc <file.dspf> [-o outdir] [-v]
```

| Flag | Description |
|------|-------------|
| `-o dir` | Write output files to `dir` (default: same directory as source) |
| `-v`, `--version` | Print version and exit |

`dspfc` detects the source format from the file content — no flags needed:
- First non-blank line is `**FREE` → free-format syntax
- Column 5 of the first non-blank line is `A` → fixed-format (DDS A-spec columns)

```bash
dspfc custmenu.dspf              # **FREE header → free-format
dspfc custmenu_fixed.dspf        # no **FREE → fixed-format
dspfc custmenu.dspf -o build/    # output to build/
dspfc -v
```

For each input file, two output files are written:

| Output | Purpose |
|--------|---------|
| `<name>.dspfd` | JSON descriptor — read by the runtime |
| `<name>_dspf.h` | C++ buffer header — included by generated RPG code |

---

## Free-Format Syntax

Free-format source begins with `**FREE` on the first line — the same convention as RPG IV. Comments start with `//`. The syntax is case-insensitive.

### File Structure

```dspf
**FREE

// Optional comments

RECORD <name> [SUBFILE]
  <record-items>
END-RECORD

RECORD <name>
  <record-items>
END-RECORD
```

A file may contain one or more `RECORD ... END-RECORD` blocks.

### Record Items

Inside a record, the following items may appear in any order:

| Item | Description |
|------|-------------|
| `SCREEN SIZE(rows cols)` | Declares the screen dimensions (default: 24 80) |
| `TITLE 'text'` | Record title string (used in descriptors and as a caption) |
| `LITERAL ROW(r) COL(c) 'text'` | Static screen text at position r, c |
| `FIELD name type usage ROW(r) COL(c)` | Input/output field |
| `KEY name INDICATOR(nn)` | Function key with indicator number |
| `SFLCTL recordname` | Marks this record as an SFLCTL controlling the named SFL |
| `SFLPAG(n)` | Subfile page size |
| `SFLSIZ(n)` | Total subfile record capacity |

### LITERAL

```dspf
LITERAL ROW(1)  COL(30)  'MAIN MENU'
LITERAL ROW(24) COL(2)   'F3=Exit   F12=Cancel'
```

A literal may carry keywords after the string:

```dspf
LITERAL ROW(24) COL(2)  'F6=Save'  COND(*IN50)
```

### FIELD

```dspf
FIELD <name> <type> <usage> ROW(r) COL(c) [keywords...]
```

**Types:**

| Type | Example | Description |
|------|---------|-------------|
| `CHAR(n)` | `CHAR(10)` | Character, length n |
| `ZONED(n:d)` | `ZONED(9:2)` | Zoned decimal, n digits, d decimals |
| `PACKED(n:d)` | `PACKED(9:2)` | Packed decimal, n digits, d decimals |
| `INT(n)` | `INT(10)` | Binary integer (4 or 8 bytes) |

**Usage:**

| Usage | Description |
|-------|-------------|
| `INPUT` | Read-only from the program's perspective; user types into it |
| `OUTPUT` | Program writes it; user cannot modify |
| `BOTH` | Program reads and writes; user can modify |
| `HIDDEN` | Not displayed; carries a value (e.g., SFLRCDNBR) |

**Field keywords** are appended after the column:

```dspf
FIELD ERRMSG  CHAR(78)   OUTPUT  ROW(24) COL(2)   COLOR(RED)
FIELD CUSTBAL ZONED(9:2) OUTPUT  ROW(6)  COL(46)  EDTCDE(1)
FIELD ORDNO   CHAR(10)   BOTH    ROW(3)  COL(17)  COND(*IN03)
```

### KEY

```dspf
KEY F3   INDICATOR(03)
KEY F12  INDICATOR(12)
KEY ENTER
```

When a function key is pressed, the indicator specified in `INDICATOR(nn)` is set on return. If no `INDICATOR` clause is present, the indicator is inferred from the key name (`F3` → indicator 3, `F12` → indicator 12, etc.).

### Complete Example

```dspf
**FREE

RECORD MAINMENU
  SCREEN SIZE(24 80)
  TITLE 'Customer Information System'

  LITERAL  ROW(1)  COL(25)  'CUSTOMER INFORMATION SYSTEM'
  LITERAL  ROW(3)  COL(2)   'Select one of the following:'
  LITERAL  ROW(5)  COL(5)   '1. Customer Inquiry'
  LITERAL  ROW(6)  COL(5)   '2. Add Customer'
  LITERAL  ROW(9)  COL(2)   'Option . . .'
  FIELD OPTION  CHAR(1)   INPUT   ROW(9)  COL(16)

  LITERAL  ROW(24) COL(2)  'F3=Exit   F12=Cancel'
  KEY F3   INDICATOR(03)
  KEY F12  INDICATOR(12)
END-RECORD

RECORD CUSTDSP
  SCREEN SIZE(24 80)
  TITLE 'Customer Display'

  LITERAL  ROW(1)  COL(30)  'CUSTOMER DISPLAY'
  LITERAL  ROW(3)  COL(2)   'Customer Number:'
  FIELD CUSTNO    CHAR(10)   BOTH    ROW(3)  COL(20)
  LITERAL  ROW(4)  COL(2)   'Name . . . . :'
  FIELD CUSTNAME  CHAR(50)   BOTH    ROW(4)  COL(20)
  LITERAL  ROW(5)  COL(2)   'Balance  . . :'
  FIELD CUSTBAL   ZONED(9:2) BOTH    ROW(5)  COL(20)  EDTCDE(1)
  FIELD ERRMSG    CHAR(78)   OUTPUT  ROW(24) COL(2)   COLOR(RED)

  LITERAL  ROW(23) COL(2)  'F3=Exit   F6=Save   F12=Cancel'
  KEY F3   INDICATOR(03)
  KEY F6   INDICATOR(06)
  KEY F12  INDICATOR(12)
END-RECORD
```

---

## Fixed-Format Syntax

Files without a `**FREE` header are treated as fixed-format — the column-fixed DDS A-spec layout used by IBM i source members. This lets you compile existing DDS source directly without conversion, just rename the file to `.dspf`.

### Column Layout

DDS source uses fixed columns (1-based):

| Columns | Content |
|---------|---------|
| 1–5 | Sequence number (ignored) |
| 6 | Form type — must be `A` |
| 7 | `*` = comment line |
| 8–16 | Conditioning / option indicators (cols 7–9, 0-based) |
| 17 | Name type: `R` = record format, blank = field/literal |
| 19–28 | Field or record name |
| 30–34 | Field length |
| 35 | Data type (`A`, `S`, `P`, `B`, `F`) |
| 36–37 | Decimal positions |
| 38 | Usage (`I`, `O`, `B`, `H`) |
| 39–41 | Row |
| 42–44 | Column |
| 45–80 | Keywords |

> All column numbers here are 1-based as shown in IBM documentation; internally `dspfc` uses 0-based offsets.

### Record Definition

```dspf
     A          R MAINMENU                  TEXT('Customer Menu')
```

A line with `R` in column 17 starts a new record format. The name appears in columns 19–28. Keywords in columns 45–80 may include `SFL`, `SFLCTL(name)`, `SFLPAG(n)`, `SFLSIZ(n)`, `TEXT('...')`.

### Field Definition

```dspf
     A            OPTION         1A  I  9 16
     A            CUSTBAL        9S 2B  5 20  EDTCDE(1)
```

- Length in columns 30–34, data type in column 35 (`A`=char, `S`=zoned, `P`=packed, `B`=binary, `F`=float)
- Decimal places in columns 36–37
- Usage in column 38
- Row in columns 39–41, column in columns 42–44

### Literals

Lines with no field name but with row and column numbers produce literals. The text appears as a quoted string in the keyword area:

```dspf
     A                                  1 30'CUSTOMER INFORMATION SYSTEM'
     A                                  9  2'Option . . .'
```

### Function Keys

Function keys are declared with `CF` (Command Function) or `CA` (Command Attention) keywords in the keyword area. They can appear on the record definition line or on keyword-only continuation lines.

- **`CF`** — key returns all field values to the program (same as EXFMT)
- **`CA`** — key signals attention only; field values are not returned

```dspf
     A          R MAINMENU
     A                                        CF03(03)
     A                                        CF12(12)
```

The number inside the parentheses is the response indicator that gets set when the key is pressed. If omitted, the indicator defaults to the key number.

```dspf
     A                                        CF03(03 'Exit')
     A                                        CA12(12 'Cancel')
```

The optional text label (e.g. `'Exit'`) is informational only.

### Option Indicators

Columns 7–9 (0-based) of a field or literal line hold an option indicator number. When set, the field or literal is shown; when off, it is hidden. `N` in column 7 negates the condition.

```dspf
     A  50        ERRMSG        78A  O 24  2COLOR(RED)
     A N50                            22  2'Press F3 to exit'
```

- Indicator `50` on → show ERRMSG
- Indicator `50` off → show the literal

`dspfc` translates these into `COND(*IN50)` and `COND(N*IN50)` keywords in the JSON descriptor.

### Complete Fixed-Format Example

```dspf
     A*  Customer list subfile
     A          R CUSTSFL                     SFL
     A            CUSTNO         10A    O   6  2
     A            CUSTNAME       30A    O   6 14
     A            CUSTBAL         9S 2   O   6 46  EDTCDE(1)
     A          R CUSTCTL                     SFLCTL(CUSTSFL)
     A                                        SFLPAG(10)
     A                                        SFLSIZ(100)
     A                                        TEXT('Customer List')
     A                                        CF03(03 'Exit')
     A                                        CF12(12 'Cancel')
     A                                   1 30'CUSTOMER LIST'
     A                                   4  2'Number'
     A                                   4 14'Name'
     A                                   4 46'Balance'
```

---

## Record Types

Every record has a `"type"` field in the JSON descriptor:

| Type | Free-format | Fixed-format keyword | Description |
|------|-------------|----------------------|-------------|
| `normal` | Default | (none) | Standard display record |
| `sfl` | `RECORD name SUBFILE` | `SFL` on record line | Subfile data record |
| `sflctl` | `SFLCTL recordname` | `SFLCTL(name)` on record line | Subfile control record |

---

## Fields

### Data Types in Generated C++

| DSPF type | C++ type in `_dspf.h` |
|-----------|----------------------|
| `CHAR(n)` | `char name[n+1]` |
| `ZONED(n:d)` with d=0 | `long name` |
| `ZONED(n:d)` with d>0 | `double name` |
| `PACKED(n:d)` with d=0 | `long name` |
| `PACKED(n:d)` with d>0 | `double name` |
| `INT(n)` | `long name` |
| `HIDDEN` | excluded from struct |

### Supported Field Keywords

| Keyword | Description |
|---------|-------------|
| `COLOR(color)` | Display color: `RED`, `GREEN`, `BLUE`, `WHITE`, `TURQ`, `YELLOW`, `PINK` |
| `DSPATR(attr)` | Display attribute: `HI` (bright), `BL` (blink), `UL` (underline), `RI` (reverse) |
| `EDTCDE(code)` | Edit code for numeric formatting (see [Numeric Formatting](#numeric-formatting--edtcde-and-edtwrd)) |
| `EDTWRD('mask')` | Edit word for numeric formatting |
| `COND(*INnn)` | Show field only when indicator nn is on |
| `COND(N*INnn)` | Show field only when indicator nn is off |
| `TEXT('text')` | Descriptive text (informational; not displayed) |

---

## Literals

Literals are static screen text. In the JSON descriptor each literal carries a `keywords` array, which may include `COND` entries.

```dspf
// Always shown
LITERAL  ROW(1)  COL(30)  'MAIN MENU'

// Shown only when *IN50 is on
LITERAL  ROW(22) COL(2)  'F6=Save'  COND(*IN50)

// Shown only when *IN90 is off
LITERAL  ROW(23) COL(2)  'Press Enter to continue'  COND(N*IN90)
```

---

## Function Keys

Function key definitions translate to entries in the `"keys"` array of the JSON descriptor. At runtime, pressing the assigned key sets the corresponding indicator and returns from the EXFMT call.

```dspf
KEY F3   INDICATOR(03)
KEY F6   INDICATOR(06)
KEY F12  INDICATOR(12)
KEY ENTER
```

On return from EXFMT, the RPG program checks `*IN03`, `*IN06`, etc. to determine which key was pressed.

---

## Subfiles

A subfile is a scrollable list of records. It requires two record definitions:

- An **SFL** record — contains the fields for one data row
- An **SFLCTL** record — controls the subfile display (headings, page size, function keys)

### Free-Format

```dspf
RECORD CUSTSFL SUBFILE
  FIELD CUSTNO    CHAR(10)   OUTPUT  ROW(6)  COL(2)
  FIELD CUSTNAME  CHAR(30)   OUTPUT  ROW(6)  COL(14)
  FIELD CUSTBAL   ZONED(9:2) OUTPUT  ROW(6)  COL(46)  EDTCDE(1)
END-RECORD

RECORD CUSTCTL
  SFLCTL CUSTSFL
  SFLPAG(10)
  SFLSIZ(100)
  SCREEN SIZE(24 80)
  TITLE 'Customer List'

  LITERAL  ROW(1)  COL(30)  'CUSTOMER LIST'
  LITERAL  ROW(4)  COL(2)   'Number'
  LITERAL  ROW(4)  COL(14)  'Name'
  LITERAL  ROW(4)  COL(46)  'Balance'

  KEY F3   INDICATOR(03)
  KEY F12  INDICATOR(12)
END-RECORD
```

| Keyword | Description |
|---------|-------------|
| `SFLPAG(n)` | Number of rows visible on screen at once |
| `SFLSIZ(n)` | Maximum total rows in the subfile |

### Runtime Behaviour

When an RPG program uses a subfile:

1. **WRITE to SFLCTL** — clears the subfile row store
2. **WRITE to SFL** (one call per data row) — appends each row
3. **EXFMT on SFLCTL** — displays the subfile as a scrollable table

Keyboard navigation:
- `Up` / `Down` — move one row
- `Page Up` / `Page Down` — move one page
- `Enter` or any defined function key — exits EXFMT

After EXFMT, the 1-based relative record number (RRN) of the selected row is written into any SFLCTL field named `SFLRCDNBR`.

### SFLRCDNBR

Declare `SFLRCDNBR` as a `HIDDEN` field in the SFLCTL record to receive the selected row number:

```dspf
     A          R CUSTCTL                     SFLCTL(CUSTSFL)
     A            SFLRCDNBR      4S 0  H
```

In RPG, read it after EXFMT:

```rpgle
EXFMT CUSTCTL;
IF NOT *IN03 AND NOT *IN12;
  // SFLRCDNBR contains the 1-based row number the user selected
  DSPLY ('Selected row: ' + %CHAR(SFLRCDNBR));
ENDIF;
```

### Complete Subfile Example (RPG)

```rpgle
**FREE
DCL-F CUSTLIST WORKSTN;

DCL-S i INT(10);

// Clear and populate the subfile
WRITE CUSTCTL;          // clears the subfile

FOR i = 1 TO 5;
  CUSTNO   = ('C' + %CHAR(i));
  CUSTNAME = ('Customer ' + %CHAR(i));
  CUSTBAL  = (i * 1000.00);
  WRITE CUSTSFL;        // append one row
ENDFOR;

// Display the subfile
EXFMT CUSTCTL;

IF NOT *IN03 AND NOT *IN12;
  DSPLY ('You selected row: ' + %CHAR(SFLRCDNBR));
ENDIF;

*INLR = *ON;
```

---

## Conditioning Indicators

Conditioning indicators control whether a field or literal is shown when the screen is rendered. They are stored as `COND(...)` keywords in the JSON descriptor and evaluated at runtime against the indicator array passed by the RPG program.

### Free-Format

```dspf
// Show ERRMSG only when *IN90 is on
FIELD ERRMSG  CHAR(78)  OUTPUT  ROW(24) COL(2)  COLOR(RED) COND(*IN90)

// Show 'F6=Save' only when *IN50 is on
LITERAL  ROW(22) COL(2)  'F6=Save'  COND(*IN50)

// Show warning only when *IN03 is off
LITERAL  ROW(23) COL(2)  'Unsaved changes!'  COND(N*IN03)
```

### Fixed-Format — Option Indicators

In fixed-format, conditioning uses the option indicator columns (7–9, 0-based). `N` in column 7 negates the condition.

```dspf
     A  90        ERRMSG        78A  O 24  2COLOR(RED)
     A  50                           22  2'F6=Save'
     A N03                           23  2'Unsaved changes!'
```

`dspfc` translates these to the same `COND(*IN90)`, `COND(*IN50)`, `COND(N*IN03)` keywords as the free-format form.

### RPG Integration

Before each EXFMT/WRITE/READ call, OpenRPG automatically passes the current indicator array to the runtime:

```rpgle
*IN90 = *ON;   // turn on error indicator
ERRMSG = 'Customer not found';
EXFMT CUSTDSP; // ERRMSG is shown because *IN90 is on

*IN90 = *OFF;  // clear error
ERRMSG = ' ';
EXFMT CUSTDSP; // ERRMSG is hidden
```

---

## Numeric Formatting — EDTCDE and EDTWRD

### EDTCDE

`EDTCDE(code)` formats a numeric field for display. Apply it to any output or both-usage field with a data type of `S` (zoned), `P` (packed), `B` (binary), or `F` (float).

```dspf
FIELD CUSTBAL  ZONED(9:2) OUTPUT  ROW(6)  COL(46)  EDTCDE(1)
FIELD INVOICE  PACKED(9:2) OUTPUT ROW(7)  COL(46)  EDTCDE(J)
```

#### Edit Code Reference

| Code | Commas | Decimal | Sign for negative | Zero fill |
|------|--------|---------|-------------------|-----------|
| `1` | Yes | Yes | (blank) | No |
| `2` | Yes | Yes | `-` trailing | No |
| `3` | No | Yes | (blank) | No |
| `4` | No | Yes | `-` trailing | No |
| `A` | Yes | Yes | `CR` trailing | No |
| `B` | Yes | Yes | `-` trailing | No |
| `C` | No | Yes | `CR` trailing | No |
| `D` | No | Yes | `-` trailing | No |
| `J` | Yes | Yes | `-` leading | No |
| `K` | Yes | Yes | `CR` trailing | No |
| `L` | No | Yes | `-` leading | No |
| `M` | No | Yes | `CR` trailing | No |
| `N`–`Q` | Same as J–M but zero-suppress | | | |
| `Y` | No | No | — | Date format with `/` separators |
| `Z` | Yes | Yes | — | Zero-suppress (suppress leading zeros) |

### EDTWRD

`EDTWRD('mask')` applies a custom edit mask to a numeric field. Digit positions in the mask are filled right-to-left with the field's digits; other characters are passed through literally.

```dspf
// Phone number format: (555) 867-5309
FIELD PHONE  ZONED(10:0) OUTPUT ROW(5) COL(10)  EDTWRD('(   )    -    ')

// Masked amount with comma and decimal
FIELD AMT  PACKED(9:2) OUTPUT ROW(6) COL(10)  EDTWRD('   ,   .  ')
```

---

## Generated Outputs

### JSON Descriptor (`.dspfd`)

The descriptor is the full machine-readable representation of the display file.

**Top-level structure:**

```json
{
  "name": "filename",
  "records": [ ... ]
}
```

**Record object:**

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Record format name (uppercase) |
| `type` | string | `"normal"`, `"sfl"`, or `"sflctl"` |
| `sfl` | string | (SFLCTL only) name of associated SFL record |
| `sflpag` | number | (SFLCTL only) page size |
| `sflsiz` | number | (SFLCTL only) total capacity |
| `title` | string | Record title |
| `screen` | object | `{ "rows": 24, "cols": 80 }` |
| `literals` | array | Static text elements |
| `fields` | array | Input/output fields |
| `keys` | array | Function key definitions |

**Literal object:**

```json
{ "row": 1, "col": 30, "text": "MAIN MENU", "keywords": [] }
{ "row": 22, "col": 2, "text": "F6=Save", "keywords": ["COND(*IN50)"] }
```

**Field object:**

```json
{
  "name": "CUSTBAL",
  "type": "S",
  "len": 9,
  "dec": 2,
  "io": "O",
  "row": 6,
  "col": 46,
  "keywords": ["EDTCDE(1)"]
}
```

| `type` value | Data type |
|---|---|
| `A` | Character |
| `S` | Zoned decimal |
| `P` | Packed decimal |
| `B` | Binary integer |
| `F` | Float |

| `io` value | Usage |
|---|---|
| `I` | Input |
| `O` | Output |
| `B` | Both (input and output) |
| `H` | Hidden |

**Key object:**

```json
{ "key": "F3", "indicator": 3 }
{ "key": "F12", "indicator": 12 }
```

### C++ Buffer Header (`_dspf.h`)

One `struct` per record format. Field types follow the mapping:

| JSON type | C++ member |
|-----------|-----------|
| `A` (char) | `char name[len+1]` |
| `S`/`P` with dec=0 | `long name` |
| `S`/`P` with dec>0 | `double name` |
| `B` | `long name` |
| `F` | `double name` |
| `H` (hidden) | *(omitted)* |

Example for CUSTMENU:

```cpp
// Auto-generated by dspfc — do not edit

struct MAINMENU_buf {
    char OPTION[2] = {};
};

struct CUSTDSP_buf {
    char   CUSTNO[11]   = {};
    char   CUSTNAME[51] = {};
    double CUSTBAL      = 0.0;
    char   ERRMSG[79]   = {};
};
```

---

## Runtime API

The display file runtime is a single header: `rpg_dspf_runtime.h`. It requires ncurses (Linux/macOS) or PDCurses (Windows).

### Linking

| Platform | Link flag |
|----------|-----------|
| macOS | `-lncurses` |
| Linux | `-lncurses` |
| Windows (PDCurses) | `-lpdcurses` |

OpenRPG adds these flags automatically when linking programs that use `DCL-F ... WORKSTN`.

### Public Functions

```cpp
void dspf_init(const char* dspfd_path);
```
Loads the `.dspfd` JSON descriptor and initialises ncurses. Call once at program startup. The path should point to the `.dspfd` file.

---

```cpp
void dspf_set_indicators(const bool* indicators, int count);
```
Passes the RPG indicator array to the runtime before each I/O operation. `count` is typically 100. OpenRPG emits this call automatically before every EXFMT, WRITE, and READ.

---

```cpp
int dspf_exfmt(const char* record_name, void* buffer);
```
Renders the named record format, waits for user input, and returns. On return:
- The buffer is updated with any values the user typed into input/both fields
- The indicator number of the key pressed (e.g., 3 for F3) is returned; 0 for Enter

---

```cpp
void dspf_write(const char* record_name, const void* buffer);
```
Writes the record to the screen without waiting for input.
- For **SFL** records: appends one row to the subfile row store
- For **SFLCTL** records: clears the subfile row store (resets for reload)
- For **normal** records: renders the screen immediately

---

```cpp
int dspf_read(const char* record_name, void* buffer);
```
Equivalent to `dspf_exfmt`. Renders the record and waits for input.

---

```cpp
void dspf_close(void);
```
Restores the terminal to its previous state. Call once at program exit.

### Default Display

Fields and literals are rendered in **green** by default. `COLOR(RED)` fields render in red. Other `COLOR` values render in their respective ncurses colors.

---

## Integration with OpenRPG

### DCL-F WORKSTN

Declare a display file in RPG with `DCL-F ... WORKSTN`. The file name maps to the compiled `.dspfd` descriptor.

```rpgle
DCL-F CUSTMENU WORKSTN;
```

OpenRPG:
1. Finds `CUSTMENU.dspfd` at runtime (searches relative to the executable, then `$RPGC_DSPF_PATH`)
2. Includes `CUSTMENU_dspf.h` for the buffer structs
3. Links with `-lncurses`

Field names from each record format become program-scope variables with their types matching the generated buffer struct. When you write to `CUSTNO`, you are writing into `CUSTDSP_buf.CUSTNO`.

### EXFMT

```rpgle
EXFMT MAINMENU;
```

Calls `dspf_exfmt("MAINMENU", &MAINMENU_buf_)` under the hood. After it returns:
- Input/both fields in the buffer hold whatever the user typed
- RPG indicators (`*IN03`, `*IN12`, etc.) reflect which key was pressed

### WRITE

```rpgle
WRITE CUSTSFL;     // append a subfile row
WRITE CUSTCTL;     // clear the subfile before reload
```

### READ

```rpgle
READ CUSTDSP;
```

Equivalent to EXFMT — renders the record and waits for input.

### Indicator Handling

Before each EXFMT/WRITE/READ on a WORKSTN file, OpenRPG emits:

```cpp
dspf_set_indicators(rpg_indicators, 100);
```

This syncs the current indicator state to the runtime so conditioning (`COND(*INxx)`) is evaluated correctly. After EXFMT returns, the return value is used to set the appropriate `*INxx` indicator.

### Full Example

**custmenu.dspf:**

```dspf
**FREE

RECORD MAINMENU
  SCREEN SIZE(24 80)
  TITLE 'Customer Information System'

  LITERAL  ROW(1)  COL(25)  'CUSTOMER INFORMATION SYSTEM'
  LITERAL  ROW(3)  COL(2)   'Select one of the following:'
  LITERAL  ROW(5)  COL(5)   '1. Customer Inquiry'
  LITERAL  ROW(6)  COL(5)   '2. Add Customer'
  LITERAL  ROW(7)  COL(5)   '3. Delete Customer'
  LITERAL  ROW(9)  COL(2)   'Option . . .'
  FIELD OPTION  CHAR(1)  INPUT  ROW(9)  COL(16)

  LITERAL  ROW(24) COL(2)  'F3=Exit   F12=Cancel'
  KEY F3   INDICATOR(03)
  KEY F12  INDICATOR(12)
END-RECORD
```

**myprog.rpgle:**

```rpgle
**FREE
DCL-F CUSTMENU WORKSTN;

DCL-S choice CHAR(1);

EXFMT MAINMENU;

IF *IN03 OR *IN12;
  DSPLY 'Exiting';
ELSE;
  choice = OPTION;
  DSPLY ('You selected: ' + choice);
ENDIF;

*INLR = *ON;
```

**Build and run:**

```bash
dspfc custmenu.dspf
rpgc myprog.rpgle
./myprog
```

---

## Testing

```bash
# Build and run all tests
make test
```

The test suite in `tests/` contains 5 golden-file tests:

| Test | File | Coverage |
|------|------|----------|
| test01 | `test01_basic.dspf` | Free-format: literals, fields, keys, COLOR |
| test02 | `test02_subfile.dspf` | Free-format: SUBFILE, SFLCTL, SFLPAG, SFLSIZ, EDTCDE |
| test03 | `test03_cond.dspf` | Free-format: COND(*INxx) on fields and literals |
| test04 | `test04_fixed_subfile.dspf` | Fixed-format: SFL/SFLCTL, option indicators |
| test05 | `CUSTMENU_fixed.dspf` + `CUSTMENU.dspf` | Both formats produce identical output |

Each test compiles the source file with `dspfc` and diffs the `.dspfd` JSON output against an expected golden file in `tests/expected/`. A mismatch prints a diff and fails the build.

### Regenerating Golden Files

If you add features that change the JSON output format, regenerate the golden files:

```bash
./dspfc tests/test01_basic.dspf           -o tests/expected/
./dspfc tests/test02_subfile.dspf         -o tests/expected/
./dspfc tests/test03_cond.dspf            -o tests/expected/
./dspfc tests/test04_fixed_subfile.dspf   -o tests/expected/
./dspfc tests/CUSTMENU.dspf               -o tests/
```
