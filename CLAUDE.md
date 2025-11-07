# OdinOS ARM64 - Project Architecture

**Target Hardware**: Apple iPhone 7 (A10 Fusion SoC) - ARMv8-A
**Language**: Odin (freestanding mode)
**Current Version**: v0.2
**Status**: QEMU-tested, iPhone 7 boot pending

---

## Overview

OdinOS is a minimal bare-metal operating system kernel written in Odin targeting ARM64 architecture, specifically designed to boot on Apple iPhone 7 hardware. The kernel demonstrates fundamental OS concepts including device tree parsing, memory management, exception handling, and hardware interfacing.

## Architecture

### Boot Sequence

1. **iBoot/QEMU** loads kernel binary to 0x40000000
2. **Boot Assembly** (src/boot/boot.s)
   - Preserves device tree address from x0
   - Detects exception level (EL1/EL2)
   - Sets up stack at `__stack_top`
   - Zeros BSS section
   - Jumps to `kernel_main` with device tree address

3. **Kernel Initialization** (src/kernel.odin)
   - Phase 1: Initialize UART (from device tree or fallback)
   - Phase 2: Parse device tree for hardware discovery
   - Phase 3: Install exception vectors
   - Phase 4: Configure and enable MMU
   - Phase 5: Halt in low-power loop

### Memory Layout

```
0x40000000 - 0x48000000  Kernel (128MB, identity mapped)
  0x40000000             _start (entry point)
  0x40001000             .text section
  0x40XXX000             .rodata section
  0x40XXX000             .data section
  0x40XXX000             .bss section
  0x47FFF000             Stack (grows downward)

0x09000000 - 0x09001000  UART (4KB, device memory)
0x44000000               Device tree (QEMU location)
```

### Exception Levels

- **Target**: EL1 (kernel mode)
- **EL2 Support**: Detected but not used (future: drop to EL1)
- **EL0 Support**: Not implemented (no user mode yet)

---

## Critical Constraints

### Freestanding Environment

- **NO standard library** - No libc, no Odin core library
- **NO runtime** - No garbage collector, no allocator (yet)
- **NO panic/assert** - These require runtime support
- **Manual memory management** - All allocations are static
- **Manual bounds checking** - Compiler cannot help

### Calling Conventions

```odin
// Exported functions MUST use C calling convention
@(export, link_name="kernel_main")
kernel_main :: proc "c" (dt_addr: uintptr) { }

// Internal functions can use Odin convention
internal_helper :: proc(x: u32) -> u32 { }

// Hardware access MUST use C convention for assembly interop
@(export, link_name="mmu_enable")
mmu_enable :: proc "c" () { }
```

### Memory Safety

```odin
// ❌ BAD: No bounds checking
values[unknown_index] = 42

// ✅ GOOD: Manual bounds check
if unknown_index < len(values) {
    values[unknown_index] = 42
} else {
    kprintln("ERROR: Index out of bounds")
    // Handle error, cannot panic!
}

// ❌ BAD: Pointer without validation
uart_base := uintptr(0x09000000)
mmio_write_u32(uart_base, 0xFF)

// ✅ GOOD: Validate before use
uart_base := fdt_find_uart()
if uart_base != 0 {
    mmio_write_u32(uart_base, 0xFF)
}
```

---

## Core Modules

### 1. MMIO (src/mmio.odin)

Memory-mapped I/O with proper ARM64 barriers.

**Key Functions**:
- `mmio_read_u32/u64/u8(addr: uintptr) -> u32/u64/u8`
- `mmio_write_u32/u64/u8(addr: uintptr, value: u32/u64/u8)`
- `arm_dmb()` - Data Memory Barrier
- `arm_dsb()` - Data Synchronization Barrier
- `arm_isb()` - Instruction Synchronization Barrier

**Performance Notes**:
- v0.1.1: Removed redundant pre-write DSB (30-50% faster writes)
- Single post-write DSB is sufficient per ARM spec

**Safety**:
- NO bounds checking on addresses
- Caller MUST ensure valid MMIO region
- Caller MUST ensure proper alignment (4-byte for u32, 8-byte for u64)

### 2. UART Driver (src/uart.odin)

PL011 UART driver for serial debugging.

**Key Functions**:
- `uart_init(base_addr: uintptr)` - Initialize UART at given address
- `uart_putc(c: u8)` - Send single character
- `uart_puts(s: cstring)` - Send null-terminated string
- `kprint/kprintln(s: cstring)` - Debug output
- `print_hex32/64(value: u32/u64)` - Hex formatting

**Configuration**:
- Baud rate: 115200
- Data: 8 bits, no parity, 1 stop bit
- Mode: Polled I/O (no interrupts)

**Optimizations**:
- v0.1.1: `@(optimization_mode="favor_size")` on hot paths
- Inlined `uart_putc` and `print_hex_digit`

### 3. Device Tree Parser (src/fdt.odin)

Flattened Device Tree parser for hardware discovery.

**Key Functions**:
- `fdt_init(dt_addr: uintptr) -> bool` - Validate and initialize
- `fdt_find_uart() -> uintptr` - Discover UART address
- `fdt_read_u32/u64(addr: uintptr) -> u32/u64` - Big-endian reads
- `cstring_equal/contains(s1, s2: cstring) -> bool` - String utilities

**Format Details**:
- Magic: 0xd00dfeed (big-endian)
- All multi-byte values are big-endian (ARM64 is little-endian!)
- Structure: Header → Memory Reservation → Structure Block → Strings

**UART Discovery**:
- Searches for nodes: "uart@", "serial@", "pl011@"
- Extracts address from "reg" property
- Supports both 32-bit and 64-bit addresses
- Falls back to 0x09000000 if not found

### 4. Exception Handling (src/exceptions.odin + src/boot/exceptions.s)

ARM64 exception vector table and handlers.

**Vector Table**:
- 2KB-aligned (`.align 11`)
- 16 entries (4 exception types × 4 sources)
- Installed via `VBAR_EL1` register

**Exception Types**:
1. Synchronous (data abort, instruction abort, syscall)
2. IRQ (normal interrupts)
3. FIQ (fast interrupts)
4. SError (system error)

**Current Behavior**:
- All exceptions print debug message to UART
- System halts in WFE loop
- TODO: Actual IRQ/FIQ handling

### 5. Memory Management (src/paging.odin + src/mmu.odin + src/boot/mmu.s)

4-level page tables with identity mapping.

**Configuration**:
- Page size: 4KB granule
- Virtual address: 48-bit
- Block size: 2MB (Level 2 descriptors)
- Translation: VA = PA (identity mapping)

**Memory Attributes**:
- Normal memory: Write-back cacheable, inner shareable
- Device memory: nGnRnE (non-gathering, non-reordering, no early write ack)

**Mapped Regions**:
- Kernel: 0x40000000-0x48000000 (128MB, executable, normal)
- UART: 0x09000000-0x09001000 (4KB, non-executable, device)

**Key Registers**:
- `MAIR_EL1`: Memory attribute indirection
- `TCR_EL1`: Translation control (granule size, VA size, cacheability)
- `TTBR0_EL1`: Page table base address
- `SCTLR_EL1`: System control (MMU enable, cache enable)

### 6. Shell Framework (src/shell.odin + src/boot/mask_interrupts.s)

Command-line shell infrastructure for user interaction.

**Key Functions**:
- `shell_init()` - Initialize shell, display banner
- `shell_run()` - Main shell loop (currently demonstrates commands)
- `buffer_add_char/remove_char()` - Input buffer management
- `parse_command()` - Parse command line into Command struct
- `execute_command()` - Dispatch to appropriate handler

**Built-in Commands**:
- `help` - List available commands
- `version` - Show OS version and target
- `clear` - Clear terminal (VT100 escape codes)
- `exit` - Graceful shutdown with UART flush

**Command System**:
- Command table: Static array of Command_Entry structs
- Handler type: `proc "c" (cmd: ^Command)`
- Case-insensitive matching
- Easy to extend (add entry to command_table)

**Input Handling**:
- 256-byte static buffer (255 + null terminator)
- Backspace support (visual feedback)
- Overflow protection
- Null termination guaranteed

**Current Limitations**:
- Interactive input (uart_getc loop) disabled due to FIQ exceptions
- Requires GIC setup and proper IRQ/FIQ handlers
- Commands work when called programmatically (demonstrated in shell_run)
- Future: Implement interrupt-driven UART RX

---

## Development Workflow

### Building

```bash
# Enter development environment
nix-shell

# Clean build
make clean && make

# Verify build
make verify

# Quick test in QEMU
make test
```

### Testing in QEMU

```bash
# Boot kernel
qemu-system-aarch64 -M virt -cpu cortex-a57 -m 128M \
  -nographic -kernel build/kernel.bin

# With device tree dump
qemu-system-aarch64 -M virt -cpu cortex-a57 -m 128M \
  -machine dumpdtb=virt.dtb

# Convert device tree to readable format
dtc -I dtb -O dts virt.dtb
```

### Debugging

```bash
# Run QEMU with GDB server
qemu-system-aarch64 -M virt -cpu cortex-a57 -m 128M \
  -nographic -kernel build/kernel.bin -s -S

# In another terminal
aarch64-unknown-linux-gnu-gdb build/kernel.elf
(gdb) target remote :1234
(gdb) break kernel_main
(gdb) continue
```

### Code Style

```odin
// ✅ GOOD: Explicit, simple code
if uart_base == 0 {
    kprintln("ERROR: UART not initialized")
    return false
}

// ✅ GOOD: Inline comments for hardware
mmio_write_u32(uart_base + UART_CR, 0)  // Disable UART
mmio_write_u32(uart_base + UART_IBRD, 13)  // 115200 baud @ 24MHz
arm_dsb()  // Ensure writes complete before continuing

// ✅ GOOD: Early returns for error handling
uart_init :: proc "c" (base_addr: uintptr) {
    if base_addr == 0 {
        return  // Cannot initialize with null address
    }
    // ... rest of initialization
}

// ❌ BAD: Complex abstractions
generic_io_operation :: proc($T: typeid, ops: []IO_Op) -> Result(T, Error) {
    // Too abstract for bare-metal!
}
```

---

## Hardware Interaction Patterns

### MMIO Register Access

```odin
// Define register offsets as constants
UART_DR   :: 0x00  // Data Register
UART_FR   :: 0x18  // Flag Register
UART_CR   :: 0x30  // Control Register

// Access with base + offset
mmio_write_u32(uart_base + UART_DR, u32(c))

// Read with barrier
flags := mmio_read_u32(uart_base + UART_FR)
if (flags & UART_FR_TXFF) != 0 {
    // TX FIFO full, wait
}
```

### Bit Manipulation

```odin
// Define bit masks as constants
UART_CR_UARTEN :: 0x01    // Bit 0: UART Enable
UART_CR_TXE    :: 0x100   // Bit 8: Transmit Enable
UART_CR_RXE    :: 0x200   // Bit 9: Receive Enable

// Combine with OR
control := UART_CR_UARTEN | UART_CR_TXE | UART_CR_RXE
mmio_write_u32(uart_base + UART_CR, control)

// Test bits with AND
if (flags & UART_FR_TXFF) != 0 {
    // Bit is set
}
```

### Volatile Loops

```odin
// Busy-wait on hardware flag
for (mmio_read_u32(uart_base + UART_FR) & UART_FR_BUSY) != 0 {
    // Wait for UART to become not busy
}

// Low-power halt loop
for {
    arm_wfe()  // Wait For Event - CPU sleeps until interrupt
}
```

---

## Testing Checklist

Before committing any changes:

- [ ] Code compiles without warnings
- [ ] Kernel size remains reasonable (< 32KB)
- [ ] `make verify` passes all symbol checks
- [ ] QEMU boot test succeeds
- [ ] UART output is correct and complete
- [ ] MMU enables without fault
- [ ] No regressions in existing functionality
- [ ] CHANGELOG.md updated
- [ ] Comments explain hardware interactions

---

## Known Limitations

### Current (v0.2)

- Device tree parser is read-only (no modification)
- UART discovery only (GIC, timers not parsed yet)
- No interrupt handling (IRQ/FIQ are stubs)
- No dynamic memory allocation
- No user mode (EL0) support
- Polled I/O only (no interrupt-driven I/O)
- QEMU-only testing (iPhone 7 boot pending)

### Future Work

1. **Hardware Discovery**
   - GIC (Generic Interrupt Controller) parsing
   - Timer discovery and configuration
   - Framebuffer/display discovery

2. **Interrupt Support**
   - GIC driver implementation
   - Timer interrupts
   - UART RX interrupts

3. **Memory Management**
   - Dynamic page allocation
   - Heap allocator
   - Virtual memory (non-identity mapping)

4. **iPhone 7 Support**
   - Obtain real device tree
   - Test on physical hardware
   - Apple-specific UART quirks
   - Touchscreen/display drivers

5. **User Mode**
   - EL0 support
   - System calls
   - Process context switching

---

## Important Registers

### System Registers

```
CurrentEL        - Current Exception Level
VBAR_EL1         - Vector Base Address (exception table)
MAIR_EL1         - Memory Attribute Indirection
TCR_EL1          - Translation Control
TTBR0_EL1        - Translation Table Base (page tables)
SCTLR_EL1        - System Control (MMU/cache enable)
ESR_EL1          - Exception Syndrome (fault info)
FAR_EL1          - Fault Address (page fault address)
ELR_EL1          - Exception Link (return address)
SPSR_EL1         - Saved Program Status
```

### Useful Values

```
EL1 = 0b0100     - Kernel mode
EL2 = 0b1000     - Hypervisor mode

TCR_EL1:
  T0SZ = 16      - 48-bit VA (64 - 16 = 48)
  TG0 = 0        - 4KB granule
  SH0 = 3        - Inner shareable
  ORGN0 = 1      - Write-back cacheable
  IRGN0 = 1      - Write-back cacheable

SCTLR_EL1:
  M = 1          - MMU enable
  C = 1          - Data cache enable
  I = 1          - Instruction cache enable
```

---

## Resources

### Documentation
- ARM Architecture Reference Manual (ARM DDI 0487)
- Cortex-A57 Technical Reference Manual
- PL011 UART Technical Reference Manual
- Device Tree Specification v0.3

### Tools
- Odin compiler: https://odin-lang.org/
- QEMU ARM64 emulation
- GCC ARM64 cross-compiler
- Device tree compiler (dtc)

### References
- Linux kernel ARM64 boot code
- Linux kernel device tree parser (libfdt)
- checkra1n jailbreak documentation

---

## Emergency Procedures

### Boot Failure

1. Check UART is working (see output?)
2. Check exception level (should be EL1)
3. Check device tree address (should be non-zero in QEMU)
4. Check MMU configuration (page tables aligned?)
5. Check symbols with `nm build/kernel.elf`

### Exception Storms

1. Exception prints should show fault type
2. Check ESR_EL1 for syndrome
3. Check FAR_EL1 for fault address
4. Common causes:
   - Misaligned MMIO access
   - Unmapped memory access
   - Invalid instruction
   - Stack overflow

### QEMU vs iPhone 7

| Feature | QEMU | iPhone 7 |
|---------|------|----------|
| UART | 0x09000000 (PL011) | TBD (Apple UART?) |
| Device tree | 0x44000000 | Passed by iBoot |
| Exception level | EL1 | TBD |
| Bootloader | QEMU firmware | iBoot |

---

**Last Updated**: 2025-11-07
**Maintainer**: OdinOS Project
**Version**: v0.2 (Device Tree Support)
