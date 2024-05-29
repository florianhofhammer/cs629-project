.PHONY: all help clean distclean

TARGET ?= mini-rv32ima
TARGETS = snake tinylisp mini-rv32ima

BUILD_DIR=build
TOOLS_DIR=../tools
SRCS = $(wildcard *.c)
OBJS = $(SRCS:%.c=$(BUILD_DIR)/%.o) $(BUILD_DIR)/dtb.o $(BUILD_DIR)/kernel.o
DEPS = $(OBJS:%.o=%.d)

CC = riscv64-unknown-elf-gcc
LD = riscv64-unknown-elf-ld
OBJCOPY = riscv64-unknown-elf-objcopy
CFLAGS = -specs=picolibc.specs \
		 --crt0=hosted \
		 -march=rv32i \
		 -mabi=ilp32 \
		 -mcmodel=medany \
		 -static \
		 -Tlink.ld \
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

mini-rv32ima: $(BUILD_DIR)/kernel.o $(BUILD_DIR)/dtb.o
$(TARGETS): % : $(BUILD_DIR)/mmio.o $(BUILD_DIR)/%.o | $(BUILD_DIR) ## Link the target
	$(CC) $(CFLAGS) -o $@ $^

img.hex: $(TOOLS_DIR)/elf2hex/elf2hex
img.hex: $(TARGET) ## Create the hex representation of the target image
	$(TOOLS_DIR)/elf2hex/elf2hex $< 0 4G $@

mem.vmh memlines.vmh: img.hex $(TOOLS_DIR)/arrange_mem/arrange_mem.py ## Prepare memory representation for our CPU
	head -n -1 $< > $@
	python3 $(TOOLS_DIR)/arrange_mem/arrange_mem.py

-include $(DEPS)

$(BUILD_DIR)/%.o: %.c | $(BUILD_DIR) ## Compile a source file into an object file and generate dependencies
	$(CC) $(CFLAGS) -o $@ -MMD -c $<

$(BUILD_DIR)/dtb.bin: default.dts | $(BUILD_DIR) ## Create the device tree blob for the kernel
	dtc -I dts -O dtb -o $@ $^ -S 1536

$(BUILD_DIR)/kernel.bin: | $(BUILD_DIR) ## Download the kernel image
	curl -L https://github.com/cnlohr/mini-rv32ima-images/raw/master/images/linux-6.1.14-rv32nommu-cnl-1.zip -o $(BUILD_DIR)/kernel.zip
	unzip -d $(BUILD_DIR) $(BUILD_DIR)/kernel.zip
	mv $(BUILD_DIR)/Image $@

%.o: %.bin ## Create the kernel object file to link into the emulator
	$(LD) -melf32lriscv -r -b binary -o $@ $^
	$(OBJCOPY) --rename-section .data=.rodata $@

$(BUILD_DIR): ## Create the build directory
	mkdir -p $@

$(TOOLS_DIR)/elf2hex/elf2hex: ## Build the elf2hex converter
	$(MAKE) -C $(TOOLS_DIR)/elf2hex

clean: ## Remove intermediate build artifacts
	-rm -rf $(BUILD_DIR)

distclean: clean ## Remove intermediate built artifacts and the final image
	-rm -f mem.vmh memlines.vmh $(TARGETS) img.hex
