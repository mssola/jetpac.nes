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
ifeq "$(DEBUG)" "1"
CCOPTS   += -g -Ln out/labels.txt
endif

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
	$(Q) rm -f config/generated.s
	$(Q) touch config/generated.s

	$(E) "	CC	 jetpac (full)"
	$(Q) $(CC65) $(CCOPTS) src/jetpac.s -C config/nrom.cfg -o out/jetpac.nes

.PHONY: build-partial
build-partial:
	$(Q) rm -f config/generated.s
	$(Q) echo "PARTIAL = 1"  >> config/generated.s

	$(E) "	CC	 jetpac (partial)"
	$(Q) $(CC65) $(CCOPTS) src/jetpac.s -C config/nrom.cfg -Wa -DPARTIAL=1 -o out/partial.nes
