.PHONY: all help clean distclean

BUILD_DIR=build
TOOLS_DIR=../tools
SRCS = $(wildcard *.c)
OBJS = $(SRCS:%.c=$(BUILD_DIR)/%.o)
DEPS = $(OBJS:%.o=%.d)

CC = riscv64-unknown-elf-gcc
CFLAGS = -specs=picolibc.specs \
		 --crt0=hosted \
		 -march=rv32i \
		 -mabi=ilp32 \
		 -mcmodel=medany \
		 -static \
		 -Tlink.ld \
		 -Werror \
		 -Wall \
		 -Wextra \
		 -Wpedantic

SOURCES=$(notdir $(wildcard $(SRCDIR)/*.c))
TESTS=$(basename $(SOURCES))
ELF=$(addprefix build/,$(TESTS))
ELF32=$(addsuffix 32,$(ELF))
HEX32=$(addsuffix .hex,$(ELF32))
ELF2HEX=../elf2hex

all: img.bin img.hex mem.vmh memlines.vmh

help: ## Show this help
	@grep -E -h '\s##\s' $(MAKEFILE_LIST) | sort | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

img.bin: $(OBJS) | $(BUILD_DIR) ## Link the target image
	$(CC) $(CFLAGS) -o $@ $^

img.hex: $(TOOLS_DIR)/elf2hex/elf2hex
img.hex: img.bin ## Create the hex representation of the target image
	$(TOOLS_DIR)/elf2hex/elf2hex $< 0 16G $@

mem.vmh memlines.vmh: img.hex $(TOOLS_DIR)/arrange_mem/arrange_mem.py ## Prepare memory representation for our CPU
	head -n -1 $< > $@
	python3 $(TOOLS_DIR)/arrange_mem/arrange_mem.py

-include $(DEPS)

$(BUILD_DIR)/%.o: %.c | $(BUILD_DIR) ## Compile a source file into an object file and generate dependencies
	$(CC) $(CFLAGS) -o $@ -MMD -c $<

$(BUILD_DIR): ## Create the build directory
	mkdir -p $@

$(TOOLS_DIR)/elf2hex/elf2hex: ## Build the elf2hex converter
	$(MAKE) -C $(TOOLS_DIR)/elf2hex

clean: ## Remove intermediate build artifacts
	-rm -rf $(BUILD_DIR)

distclean: clean ## Remove intermediate built artifacts and the final image
	-rm -f img.bin img.hex mem.vmh memlines.vmh
