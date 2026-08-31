CXX      := clang++
CXXFLAGS := -std=c++17 -Wall -Wextra -Wno-deprecated-register -Wno-unused-function

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    BREW_PREFIX := $(shell brew --prefix 2>/dev/null || echo /opt/homebrew)
    FLEX        ?= $(BREW_PREFIX)/opt/flex/bin/flex
    BISON       ?= $(BREW_PREFIX)/opt/bison/bin/bison
else ifneq (,$(MSYSTEM))
    # MSYSTEM is set by every MSYS2 shell (MINGW64, UCRT64, CLANGARM64, ...) —
    # more reliable than grepping `uname -s`, which reports a different
    # prefix per environment (e.g. CLANGARM64_NT-... on Windows ARM64) and
    # would silently miss anything but literal "MINGW".
    FLEX        ?= flex
    BISON       ?= bison
    # Static-link the C++ runtime so dspfc.exe doesn't depend on MSYS2's
    # libc++.dll/libstdc++-6.dll/libwinpthread-1.dll being present on the
    # target machine — the NSIS installer only ships the exe itself.
    LDFLAGS     ?= -static
    ifeq ($(MSYSTEM),CLANGARM64)
        CXX := clang++
    else
        CXX := g++
    endif
else
    FLEX        ?= flex
    BISON       ?= bison
    CXX         := g++
endif

SRCDIR   := src
BUILDDIR := build
TARGET   := dspfc

SRCS := $(BUILDDIR)/lexer.cpp \
        $(BUILDDIR)/parser.cpp \
        $(SRCDIR)/dds_reader.cpp \
        $(SRCDIR)/codegen.cpp \
        $(SRCDIR)/main.cpp

OBJS := $(BUILDDIR)/lexer.o \
        $(BUILDDIR)/parser.o \
        $(BUILDDIR)/dds_reader.o \
        $(BUILDDIR)/codegen.o \
        $(BUILDDIR)/main.o

# When checked out as a git submodule, .git is a file (not a directory)
# pointing at the superproject's gitdir. In that case inherit the
# superproject's version so `dspfc -v` matches `rpgc -v` when the two are
# built and shipped together — otherwise fall back to our own tags.
ifeq ($(shell test -f .git && echo submodule),submodule)
    VERSION ?= $(shell git -C .. describe --tags --always 2>/dev/null || echo "dev")
else
    VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo "dev")
endif
CXXFLAGS += -DDSPFC_VERSION='"$(VERSION)"'

PREFIX   ?= /usr/local
BINDIR   := $(PREFIX)/bin
DATADIR  := $(PREFIX)/share/rpgc/runtime

all: $(TARGET)

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

$(BUILDDIR)/parser.cpp $(BUILDDIR)/parser.h: $(SRCDIR)/parser.y | $(BUILDDIR)
	$(BISON) --defines=$(BUILDDIR)/parser.h -o $(BUILDDIR)/parser.cpp $<

$(BUILDDIR)/lexer.cpp: $(SRCDIR)/lexer.l $(BUILDDIR)/parser.h | $(BUILDDIR)
	$(FLEX) -o $@ $<

$(BUILDDIR)/lexer.o: $(BUILDDIR)/lexer.cpp
	$(CXX) $(CXXFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(BUILDDIR)/parser.o: $(BUILDDIR)/parser.cpp $(SRCDIR)/ast.h
	$(CXX) $(CXXFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(BUILDDIR)/dds_reader.o: $(SRCDIR)/dds_reader.cpp $(SRCDIR)/dds_reader.h $(SRCDIR)/ast.h
	$(CXX) $(CXXFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(BUILDDIR)/codegen.o: $(SRCDIR)/codegen.cpp $(SRCDIR)/codegen.h $(SRCDIR)/ast.h
	$(CXX) $(CXXFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(BUILDDIR)/main.o: $(SRCDIR)/main.cpp $(SRCDIR)/ast.h $(SRCDIR)/codegen.h $(SRCDIR)/dds_reader.h
	$(CXX) $(CXXFLAGS) -I$(SRCDIR) -I$(BUILDDIR) -c -o $@ $<

$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

clean:
	rm -rf $(BUILDDIR) $(TARGET)

install: $(TARGET)
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(TARGET) $(DESTDIR)$(BINDIR)/$(TARGET)
	install -d $(DESTDIR)$(DATADIR)
	install -m 644 runtime/rpg_dspf_runtime.h $(DESTDIR)$(DATADIR)/

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(TARGET)
	rm -f $(DESTDIR)$(DATADIR)/rpg_dspf_runtime.h

# Prefer the sibling OpenRPG checkout over a system-installed rpgc: rpgc's
# own runtime_dir resolution checks (cwd)/runtime before its installed
# fallback location, and OpenDSPF's own runtime/ subdirectory (real, but
# containing only rpg_dspf_runtime.h) satisfies that check and wrongly
# shadows a complete installed copy — breaking a system-installed rpgc's
# ability to find rpg_runtime.h and friends when invoked from here. The
# sibling checkout's own runtime/ dir doesn't have this false-positive
# problem, so prefer it whenever present.
RPGC ?= $(shell [ -x ../rpgc ] && echo ../rpgc || { [ -x ../OpenRPG/rpgc ] && echo ../OpenRPG/rpgc; } || which rpgc 2>/dev/null || echo ../rpgc)

test: $(TARGET)
	@DSPFC=./$(TARGET) bash tests/run_tests.sh
	@echo "--- RPG integration: compile test_exfmt.rpgle ---"
	@if [ -x "$(RPGC)" ]; then \
	    $(RPGC) tests/test_exfmt.rpgle -o /tmp/test_exfmt && \
	    echo "OK: RPG compile succeeded (run /tmp/test_exfmt to test interactively)"; \
	else \
	    echo "SKIP: rpgc not found (set RPGC=/path/to/rpgc to enable)"; \
	fi
	@echo "--- Interactive runtime tests (real ncurses keystrokes) ---"
	@DSPFC=./$(TARGET) RPGC=$(RPGC) bash tests/run_interactive.sh

.PHONY: all clean install uninstall test
