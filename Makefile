#-------------------------------------------------------------------------
#
# Makefile for pg_ttl_index PostgreSQL extension
#
# This Makefile uses the PostgreSQL extension building infrastructure (PGXS).
# To build the extension, you need PostgreSQL development headers installed.
#
# Build commands:
#   make              - Compile the extension
#   make install      - Install to PostgreSQL
#   make installcheck - Run regression tests
#   make clean        - Remove build artifacts
#
#-------------------------------------------------------------------------

# Extension name and version
EXTENSION = pg_ttl_index
MODULE_big = pg_ttl_index

# Object files to compile
OBJS = src/pg_ttl_index.o src/worker.o src/api.o src/utils.o

# SQL files for all versions
DATA = pg_ttl_index--2.0.0.sql

# Documentation
DOCS = README.md CONTRIBUTING.md

# Extension description
PGFILEDESC = "pg_ttl_index - TTL index extension for automatic data expiration"

# Regression tests (uncomment when tests are added)
REGRESS = test_ttl
REGRESS_OPTS = --inputdir=test

# Extra files to clean
EXTRA_CLEAN = src/*.o src/*.bc

# PostgreSQL configuration
PG_CPPFLAGS = -I./src
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)

# Disable LLVM bitcode compilation (requires clang, not always available in CI)
# Must be set before including PGXS
override WITH_LLVM = no

include $(PGXS)

#-------------------------------------------------------------------------
# Development and maintenance targets
#-------------------------------------------------------------------------

# Create a distribution archive
.PHONY: dist
dist: clean
	@echo "Creating distribution archive..."
	@mkdir -p dist
	@git archive --format=zip --prefix=$(EXTENSION)/ -o dist/$(EXTENSION)-$(shell git describe --tags --always).zip HEAD
	@echo "Archive created: dist/$(EXTENSION)-$(shell git describe --tags --always).zip"

# Development build with more warnings
.PHONY: dev
dev: CFLAGS += -Wall -Wextra -Werror -g
dev: all
	@echo "Development build complete with extra warnings"

# Quick rebuild (useful during development)
.PHONY: rebuild
rebuild: clean all install
	@echo "Extension rebuilt and installed"

# Check code style (requires clang-format)
.PHONY: format
format:
	@if command -v clang-format >/dev/null 2>&1; then \
		echo "Formatting C code in src/..."; \
		clang-format -i src/*.c src/*.h; \
	else \
		echo "clang-format not found, skipping formatting"; \
	fi

# Show extension info
.PHONY: info
info:
	@echo "Extension: $(EXTENSION)"
	@echo "Version: $(shell grep default_version $(EXTENSION).control | cut -d"'" -f2)"
	@echo "PostgreSQL: $(shell $(PG_CONFIG) --version)"
	@echo "Install path: $(shell $(PG_CONFIG) --sharedir)/extension"
	@echo "Library path: $(shell $(PG_CONFIG) --pkglibdir)"

# Help target
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  make              - Build the extension"
	@echo "  make install      - Install to PostgreSQL"
	@echo "  make installcheck - Run regression tests"
	@echo "  make clean        - Remove build artifacts"
	@echo "  make dev          - Development build with extra warnings"
	@echo "  make rebuild      - Clean, build, and install"
	@echo "  make dist         - Create distribution archive"
	@echo "  make format       - Format C code (requires clang-format)"
	@echo "  make info         - Show extension information"
	@echo ""
	@echo "Environment variables:"
	@echo "  PG_CONFIG=path   - Path to pg_config (default: pg_config)"