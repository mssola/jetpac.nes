V =
ifeq ($(strip $(V)),)
	E = @echo
	Q = @
else
	E = @\#
	Q =
endif

# CC65 is set to `xa65` if that exists, otherwise we resort to `cl65` by default.
XA65_BIN := $(shell command -v xa65 2>/dev/null)
ifneq ($(XA65_BIN),)
	CC65   ?= xa65
else
	CC65   ?= cl65
endif

# NOTE: you can configure `CC65` and `CCOPTS` with the compiler and its options
# that you might require.
CCOPTS ?= --target nes

# Be strict when using xa65, and extra verbose if V=1.
ifeq ($(CC65),xa65)
	CCOPTS += --strict --stats
endif

# Ruby is used to generate the files on `config/values/`. If it can't be found,
# a warning will be echo'ed.
#
# NOTE: you can actually set RUBY as an argument to `make` if you want to pass
# something special to it.
RUBY ?= ruby
HAS_RUBY := $(shell command -v $(RUBY) >/dev/null 2>&1 && echo true || echo false)

##
# Variables for building the game.
LEVEL ?= 0
LEVELS := $(shell seq 0 7)

##
# all: clean the workspace and build all ROM files.

.PHONY: all
all: clean deps build

##
# clean & deps: clean the workspace and check that all dependencies are met.

.PHONY: clean
clean:
	$(Q) rm -rf out
	$(Q) find . -type f -name "*.o" -delete
	$(Q) find . -type f -name "*.nes" -delete
	$(Q) rm -rf .nasm/
	$(Q) mkdir -p out/

.PHONY: deps
deps:
	@which $(CC65) >/dev/null 2>/dev/null || (echo "ERROR: '$(CC65)' not found." && false)

##
# Generate configuration values in 'config/values/'.

.PHONY: gen-values
gen-values:
ifeq ($(HAS_RUBY),true)
	$(E) "	GEN	 config/values"
	$(Q) ruby bin/values.rb
else
	$(Q) echo "WARNING: '$(RUBY)' not found; files under 'config/values/' will not be generated."
endif

##
# build: create a ROM file for NTSC and PAL, while creating a DEV one for
# testing purposes.

.PHONY: build
build: gen-values build-partial build-pal build-full

.PHONY: build-full
build-full:
	$(Q) rm -f config/generated.s
	$(Q) echo "HZ = 60" >> config/generated.s
	$(Q) echo "LEVEL = $(LEVEL)" >> config/generated.s

	$(E) "	CC	 jetpac (NTSC)"
	$(Q) $(CC65) $(CCOPTS) src/jetpac.s -C config/nrom.cfg -o "out/Jetpac (NTSC).nes" 1>/dev/null

.PHONY: build-partial
build-partial:
	$(Q) rm -f config/generated.s
	$(Q) echo "PARTIAL = 1"  >> config/generated.s
	$(Q) echo "HZ = 60" >> config/generated.s
	$(Q) echo "LEVEL = $(LEVEL)" >> config/generated.s

	$(E) "	CC	 jetpac (partial)"
	$(Q) $(CC65) $(CCOPTS) src/jetpac.s -C config/nrom.cfg -o "out/Jetpac (DEV).nes" 1>/dev/null

.PHONY: build-pal
build-pal:
	$(Q) rm -f config/generated.s
	$(Q) echo "PAL = 1"  >> config/generated.s
	$(Q) echo "HZ = 50" >> config/generated.s
	$(Q) echo "LEVEL = $(LEVEL)" >> config/generated.s

	$(E) "	CC	 jetpac (PAL)"
	$(Q) $(CC65) $(CCOPTS) src/jetpac.s -C config/nrom.cfg -o "out/Jetpac (PAL).nes" 1>/dev/null

##
# release: generate ROM files which are only interesting for releases.

release: clean deps gen-values build-full build-pal

##
# each: create a ROM file for each level.

EACH_TARGETS := $(foreach i,$(LEVELS),out/jetpac.$(i).nes)

.PHONY: each
each: clean deps gen-values $(EACH_TARGETS)

out/jetpac.%.nes:
	$(Q) $(MAKE) build-full LEVEL=$*
	$(Q) mv "out/Jetpac (NTSC).nes" "$@"
