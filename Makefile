CXX      := clang++
CXXFLAGS := -std=c++17 -Wall -Wextra -Wno-deprecated-register -Wno-unused-function

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    BREW_PREFIX := $(shell brew --prefix 2>/dev/null || echo /opt/homebrew)
    FLEX        ?= $(BREW_PREFIX)/opt/flex/bin/flex
    BISON       ?= $(BREW_PREFIX)/opt/bison/bin/bison
else ifneq (,$(findstring MINGW,$(UNAME_S)))
    FLEX        ?= flex
    BISON       ?= bison
    CXX         := g++
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

VERSION := $(shell git describe --tags --always 2>/dev/null || echo "dev")
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
	$(CXX) $(CXXFLAGS) -o $@ $^

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

RPGC ?= $(shell which rpgc 2>/dev/null || echo ../OpenRPG/rpgc)

test: $(TARGET)
	@DSPFC=./$(TARGET) bash tests/run_tests.sh
	@echo "--- RPG integration: compile test_exfmt.rpgle ---"
	@if [ -x "$(RPGC)" ]; then \
	    $(RPGC) tests/test_exfmt.rpgle -o /tmp/test_exfmt && \
	    echo "OK: RPG compile succeeded (run /tmp/test_exfmt to test interactively)"; \
	else \
	    echo "SKIP: rpgc not found (set RPGC=/path/to/rpgc to enable)"; \
	fi

.PHONY: all clean install uninstall test
