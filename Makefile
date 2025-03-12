V =
ifeq ($(strip $(V)),)
	E = @echo
	Q = @
else
	E = @\#
	Q =
endif

CC65   ?= cl65
CCOPTS ?= --target nes

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
	@which $(CC65) >/dev/null 2>/dev/null || (echo "ERROR: $(CC65) not found." && false)

.PHONY: build
build: build-full build-partial

.PHONY: build-full
build-full:
	$(E) "	CC	 jetpac (full)"
	$(Q) $(CC65) $(CCOPTS) src/jetpac.s -C config/nrom.cfg -o out/jetpac.nes

.PHONY: build-partial
build-partial:
	$(E) "	CC	 jetpac (partial)"
	$(Q) $(CC65) $(CCOPTS) src/jetpac.s -C config/nrom.cfg --asm-define PARTIAL=1 -o out/partial.nes
