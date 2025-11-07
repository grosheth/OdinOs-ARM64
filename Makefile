# OdinOS Makefile - iPhone 7 / ARM64
# Target: Apple iPhone 7 (A10 Fusion chip - ARMv8-A)

# Toolchain configuration
ODIN := odin
CROSS_COMPILE ?= aarch64-unknown-linux-gnu-
CC := $(CROSS_COMPILE)gcc
LD := $(CROSS_COMPILE)ld
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump

# Directories
SRC_DIR := src
BUILD_DIR := build
BOOT_DIR := $(SRC_DIR)/boot

# Target configuration
TARGET := aarch64
KERNEL_BIN := $(BUILD_DIR)/kernel.bin
KERNEL_ELF := $(BUILD_DIR)/kernel.elf

# Odin build flags
ODIN_FLAGS := -target:freestanding_arm64 \
              -build-mode:obj \
              -no-crt \
              -reloc-mode:pic \
              -disable-assert \
              -o:speed

# Linker flags
LDFLAGS := -nostdlib \
           -T $(SRC_DIR)/linker.ld \
           -Map=$(BUILD_DIR)/kernel.map

# QEMU configuration for iPhone 7 / ARM64 testing
QEMU := qemu-system-aarch64
QEMU_FLAGS := -machine virt \
              -cpu cortex-a72 \
              -m 2G \
              -nographic \
              -serial mon:stdio \
              -kernel $(KERNEL_BIN)

# Colors for output
GREEN := \033[0;32m
BLUE := \033[0;34m
YELLOW := \033[0;33m
NC := \033[0m # No Color

.PHONY: all clean run debug info help

all: $(KERNEL_BIN)
	@echo "$(GREEN)✓ Build complete: $(KERNEL_BIN)$(NC)"

# Build Odin kernel code
$(BUILD_DIR)/kernel.o: $(shell find $(SRC_DIR) -name '*.odin')
	@echo "$(BLUE)Building Odin kernel code...$(NC)"
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build $(SRC_DIR) $(ODIN_FLAGS) -out:$(BUILD_DIR)/kernel.o

# Build boot assembly (if needed)
$(BUILD_DIR)/boot.o: $(BOOT_DIR)/boot.s
	@echo "$(BLUE)Building boot assembly...$(NC)"
	@mkdir -p $(BUILD_DIR)
	$(CC) -c $(BOOT_DIR)/boot.s -o $(BUILD_DIR)/boot.o

# Link kernel
$(KERNEL_ELF): $(BUILD_DIR)/kernel.o
	@echo "$(BLUE)Linking kernel...$(NC)"
	$(LD) $(LDFLAGS) -o $(KERNEL_ELF) $(BUILD_DIR)/kernel.o

# Create flat binary
$(KERNEL_BIN): $(KERNEL_ELF)
	@echo "$(BLUE)Creating kernel binary...$(NC)"
	$(OBJCOPY) -O binary $(KERNEL_ELF) $(KERNEL_BIN)
	@echo "$(GREEN)Kernel size: $$(du -h $(KERNEL_BIN) | cut -f1)$(NC)"

# Run in QEMU
run: $(KERNEL_BIN)
	@echo "$(YELLOW)Starting QEMU (use Ctrl-A X to quit)...$(NC)"
	$(QEMU) $(QEMU_FLAGS)

# Run with GDB debugging
debug: $(KERNEL_BIN)
	@echo "$(YELLOW)Starting QEMU with GDB server on port 1234...$(NC)"
	@echo "$(YELLOW)In another terminal, run: $(CROSS_COMPILE)gdb $(KERNEL_ELF) -ex 'target remote :1234'$(NC)"
	$(QEMU) $(QEMU_FLAGS) -s -S

# Show kernel information
info: $(KERNEL_ELF)
	@echo "$(BLUE)Kernel Information:$(NC)"
	@echo "ELF file: $(KERNEL_ELF)"
	@echo "Binary: $(KERNEL_BIN)"
	@file $(KERNEL_BIN)
	@echo ""
	@echo "$(BLUE)Size breakdown:$(NC)"
	@size $(KERNEL_ELF)
	@echo ""
	@echo "$(BLUE)Sections:$(NC)"
	@$(OBJDUMP) -h $(KERNEL_ELF)

# Disassemble kernel
disasm: $(KERNEL_ELF)
	@echo "$(BLUE)Disassembling kernel...$(NC)"
	$(OBJDUMP) -d $(KERNEL_ELF) > $(BUILD_DIR)/kernel.asm
	@echo "$(GREEN)Disassembly saved to $(BUILD_DIR)/kernel.asm$(NC)"

# Clean build artifacts
clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	rm -rf $(BUILD_DIR)
	@echo "$(GREEN)Clean complete$(NC)"

# Help
help:
	@echo "$(BLUE)OdinOS Makefile - iPhone 7 / ARM64$(NC)"
	@echo ""
	@echo "Targets:"
	@echo "  all     - Build the kernel (default)"
	@echo "  run     - Run kernel in QEMU"
	@echo "  debug   - Run kernel in QEMU with GDB server"
	@echo "  info    - Show kernel binary information"
	@echo "  disasm  - Disassemble kernel to build/kernel.asm"
	@echo "  clean   - Remove all build artifacts"
	@echo "  help    - Show this help message"
	@echo ""
	@echo "Environment variables:"
	@echo "  CROSS_COMPILE - ARM64 toolchain prefix (default: aarch64-unknown-linux-gnu-)"
	@echo ""
	@echo "Example usage:"
	@echo "  make          # Build kernel"
	@echo "  make run      # Run in QEMU"
	@echo "  make debug    # Debug with GDB"
