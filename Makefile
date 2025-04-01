V =
ifeq ($(strip $(V)),)
	E = @echo
	Q = @
else
	E = @\#
	Q =
endif

# NOTE: you can configure `CC65` and `CCOPTS` with the compiler and its options
# that you might require. Moreover, if you pass `DEBUG` to `make`, then an
# `out/labels.txt` file will be generated.
CC65   ?= cl65
CCOPTS ?= --target nes
ifeq "$(DEBUG)" "1"
CCOPTS   += -g -Ln out/labels.txt
endif

# Ruby is used to generate the files on `config/values/`. If it can't be found,
# a warning will be echo'ed.
#
# NOTE: you can actually set RUBY as an argument to `make` if you want to pass
# something special to it.
RUBY ?= ruby
HAS_RUBY := $(shell command -v $(RUBY) >/dev/null 2>&1 && echo true || echo false)

.PHONY: all
all: clean deps build

.PHONY: clean
clean:
	@rm -rf out
	@find . -type f -name "*.o" -delete
	@find . -type f -name "*.nes" -delete
	@mkdir -p out/

.PHONY: deps
deps:
	@which $(CC65) >/dev/null 2>/dev/null || (echo "ERROR: '$(CC65)' not found." && false)

.PHONY: gen-values
gen-values:
ifeq ($(HAS_RUBY),true)
	$(E) "	GEN	 config/values"
	$(Q) ruby bin/values.rb
else
	@(Q) echo "WARNING: '$(RUBY)' not found; files under 'config/values/' will not be generated."
endif

.PHONY: build
build: gen-values build-full build-partial build-pal

.PHONY: build-full
build-full:
	$(Q) rm -f config/generated.s
	$(Q) echo "HZ = 60" >> config/generated.s

	$(E) "	CC	 jetpac (NTSC)"
	$(Q) $(CC65) $(CCOPTS) src/jetpac.s -C config/nrom.cfg -o "out/Jetpac (NTSC).nes"

.PHONY: build-partial
build-partial:
	$(Q) rm -f config/generated.s
	$(Q) echo "PARTIAL = 1"  >> config/generated.s
	$(Q) echo "HZ = 60" >> config/generated.s

	$(E) "	CC	 jetpac (partial)"
	$(Q) $(CC65) $(CCOPTS) src/jetpac.s -C config/nrom.cfg -o "out/Jetpac (DEV).nes"

.PHONY: build-pal
build-pal:
	$(Q) rm -f config/generated.s
	$(Q) echo "PAL = 1"  >> config/generated.s
	$(Q) echo "HZ = 50" >> config/generated.s

	$(E) "	CC	 jetpac (PAL)"
	$(Q) $(CC65) $(CCOPTS) src/jetpac.s -C config/nrom.cfg -o "out/Jetpac (PAL).nes"
