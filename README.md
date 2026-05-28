# OpenDSPF

OpenDSPF is an open-source compiler for IBM i display file source — both free-format `.dspf` and DDS A-spec `.dds`. The `dspfc` binary reads display file source, validates it, and emits two portable artifacts: a `.dspfd` JSON descriptor and a `_dspf.h` C++ buffer header. Programs compiled with [OpenRPG](https://github.com/danlong005/OpenRPG) use these artifacts plus the included ncurses runtime to render interactive terminal screens — no IBM i required.

---

## Quick Start

**Write a display file (free-format):**

```dspf
**DSPF

RECORD MAINMENU
  SCREEN SIZE(24 80)
  TITLE 'Main Menu'

  LITERAL  ROW(1)  COL(30)  'MAIN MENU'
  LITERAL  ROW(3)  COL(2)   'Option:'
  FIELD OPTION  CHAR(1)  INPUT  ROW(3)  COL(10)

  LITERAL  ROW(24) COL(2)  'F3=Exit'
  KEY F3  INDICATOR(03)
END-RECORD
```

**Compile it:**

```bash
dspfc mainmenu.dspf
```

**Outputs:**
- `mainmenu.dspfd` — JSON descriptor (consumed by the runtime)
- `mainmenu_dspf.h` — C++ buffer structs (consumed by generated RPG code)

**Use it from RPG (with OpenRPG):**

```rpgle
**FREE
DCL-F MAINMENU WORKSTN;

EXFMT MAINMENU;

IF *IN03;
  DSPLY 'Exiting';
ELSE;
  DSPLY ('Option selected: ' + OPTION);
ENDIF;

*INLR = *ON;
```

```bash
rpgc myprog.rpgle
./myprog
```

---

## Quick Start — DDS A-Spec (fixed-format)

If you have existing IBM i DDS source members, `dspfc` reads them directly. DDS uses fixed columns: the form type (`A`) in column 6, `R` / `K` in column 17 to mark record/key lines, field lengths and types in columns 30–38, row/column in 39–44, and keywords starting at column 45.

```dds
     A*  Customer menu — IBM i DDS A-spec
     A          R MAINMENU                  TEXT('Customer Information System')
     A                                  1 25'CUSTOMER INFORMATION SYSTEM'
     A                                  3  2'Select one of the following:'
     A                                  5  5'1. Customer Inquiry'
     A                                  6  5'2. Add Customer'
     A                                  7  5'3. Delete Customer'
     A                                  9  2'Option . . .'
     A            OPTION         1A  I  9 16
     A                                 24  2'F3=Exit   F12=Cancel'
     A          K F3
     A          K F12
```

```bash
dspfc CUSTMENU.dds
```

Both formats produce the same `.dspfd` JSON descriptor and `_dspf.h` header — the RPG program is identical either way.

---

## Usage

```
dspfc <file.dspf|file.dds> [-o outdir] [-v]
```

| Flag | Description |
|------|-------------|
| `-o dir` | Write output files to `dir` (default: same directory as the source file) |
| `-v`, `--version` | Print version and exit |

`dspfc` auto-detects the source format from the file content:
- Lines starting with `**DSPF` → free-format
- Column 5 of the first non-blank line is `A` → DDS A-spec

```bash
dspfc mainmenu.dspf              # auto-detected as free-format
dspfc CUSTMENU.dds               # auto-detected as DDS A-spec
dspfc mainmenu.dspf -o build/    # write outputs to build/
dspfc -v                         # print version
```

---

## Outputs

### JSON Descriptor (`.dspfd`)

The descriptor is the canonical representation of the display file — what the runtime and OpenRPG toolchain read at runtime. It contains every record format with its literals, fields, keys, subfile metadata, and keyword lists.

```json
{
  "name": "mainmenu",
  "records": [
    {
      "name": "MAINMENU",
      "type": "normal",
      "title": "Main Menu",
      "screen": { "rows": 24, "cols": 80 },
      "literals": [
        { "row": 1, "col": 30, "text": "MAIN MENU", "keywords": [] }
      ],
      "fields": [
        { "name": "OPTION", "type": "A", "len": 1, "dec": 0, "io": "I",
          "row": 3, "col": 10, "keywords": [] }
      ],
      "keys": [
        { "key": "F3", "indicator": 3 }
      ]
    }
  ]
}
```

### C++ Buffer Header (`_dspf.h`)

One struct per record format. Fields map to C++ types: character fields → `char[len+1]`, zoned/packed → `double`, binary → `long`. Hidden fields (`H` usage) are excluded.

```cpp
struct MAINMENU_buf {
    char OPTION[2] = {};
};
```

---

## Building from Source

**Prerequisites:** C++17 compiler (clang++ or g++), Flex, Bison.

```bash
# macOS
brew install flex bison

# Linux (Debian/Ubuntu)
sudo apt install flex bison g++
```

```bash
git clone https://github.com/danlong005/OpenDSPF.git
cd OpenDSPF
make
sudo make install        # installs to /usr/local
```

The install puts `dspfc` in `$PREFIX/bin` and `rpg_dspf_runtime.h` in `$PREFIX/share/rpgc/runtime/` (where OpenRPG also looks for it).

---

## Integration with OpenRPG

OpenDSPF and [OpenRPG](https://github.com/danlong005/OpenRPG) are designed as a pair. When you compile an RPG program with `DCL-F ... WORKSTN`, OpenRPG:

1. Locates the `.dspfd` for the named file at runtime
2. Includes the generated `_dspf.h` for the buffer structs
3. Links the ncurses runtime (`-lncurses` / `-lpdcurses` on Windows)

The runtime renders screens using the JSON descriptor, handles keyboard input, evaluates conditioning indicators, formats numeric fields (EDTCDE/EDTWRD), and manages scrollable subfiles — all transparently.

See [docs/GUIDE.md](docs/GUIDE.md#integration-with-openrpg) for full details.

---

## Test Suite

```bash
make test
```

Runs 5 golden-file tests covering free-format and DDS A-spec, subfiles, conditioning indicators, and EDTCDE. Each test compiles a source file and diffs the JSON output against a checked-in expected file.

---

## Documentation

- **[User's Guide](docs/GUIDE.md)** — Full language reference with examples
- **[TODO.md](TODO.md)** — Feature tracker

---

## Trademarks

DDS, RPG, RPG IV, IBM i, AS/400, and Db2 are trademarks or registered trademarks of International Business Machines Corporation in the United States, other countries, or both.

This project is an independent, clean-room implementation. It is not affiliated with, endorsed by, sponsored by, or otherwise associated with IBM. References to IBM products and technologies are made solely for the purpose of describing compatibility and interoperability.

## License

MIT — see [LICENSE](LICENSE) for details.
