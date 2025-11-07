# OdinOS - iPhone 7 ARM64 Kernel

A bare-metal kernel for iPhone 7 (Apple A10 Fusion) written in Odin programming language.

## Target Hardware

- **Device**: iPhone 7 (iPhone9,1 / iPhone9,3)
- **SoC**: Apple A10 Fusion
- **Architecture**: ARMv8-A (64-bit ARM)
- **Cores**: 2x Hurricane (high-performance) + 2x Zephyr (efficiency)
- **Boot method**: checkra1n / checkm8 exploit chain

## Project Structure

```
OdinOs-ARM64/
├── .claude/              # AI agent configurations
│   └── prompts/          # Specialized agents for development
├── src/                  # Source code
│   ├── boot/            # Boot assembly and initialization
│   ├── drivers/         # Device drivers (UART, framebuffer, etc.)
│   ├── mm/              # Memory management
│   └── linker.ld        # Linker script
├── build/               # Build artifacts (generated)
├── shell.nix            # Nix development environment
├── Makefile             # Build system
└── README.md            # This file
```

## Development Environment

### Using Nix (Recommended for NixOS)

```bash
# Enter the development shell
nix-shell

# This provides:
# - Odin compiler with ARM64 support
# - ARM64 cross-compilation toolchain
# - QEMU for ARM64 emulation
# - Device tree tools
# - GDB for debugging
```

### Manual Setup

Requirements:
- Odin compiler (with ARM64 target support)
- ARM64 cross-compiler (aarch64-unknown-linux-gnu-gcc)
- QEMU (qemu-system-aarch64)
- GNU Make
- Device Tree Compiler (dtc)

## Building

```bash
# Build the kernel
make

# Build and run in QEMU
make run

# Build and debug with GDB
make debug

# Show kernel information
make info

# Clean build artifacts
make clean
```

## Development Workflow

### 1. Plan Your Work

Use the planner agent to break down tasks:
- Features are decomposed into atomic tasks
- Dependencies are identified
- Risk assessment is performed

### 2. Implement

The coder agent helps with:
- ARM64-specific code patterns
- MMIO (Memory-Mapped I/O) operations
- Exception handling
- Device tree parsing

### 3. Optimize

The optimizer agent reviews for:
- ARM64 performance optimizations
- Cache-friendly memory access
- NEON SIMD opportunities
- A10 Fusion-specific tuning

### 4. Security Review

The security agent audits for:
- Memory safety issues
- Privilege escalation risks
- MMIO security concerns
- ARM-specific vulnerabilities

## Getting Started

### Minimal Boot Example

1. Create `src/kernel.odin`:

```odin
package kernel

// Kernel entry point
@(export, link_name="_start")
kernel_main :: proc "c" () {
    // TODO: Initialize UART
    // TODO: Print "Hello from OdinOS!"

    // Halt
    for {}
}
```

2. Build and run:

```bash
make run
```

## Architecture Overview

### Boot Process

1. iBoot loads kernel at specified address
2. ARM64 starts in EL2 (hypervisor) or EL1 (kernel)
3. Boot assembly sets up initial stack
4. Jump to Odin `kernel_main`
5. Initialize hardware via device tree
6. Set up exception vectors
7. Enable MMU and page tables
8. Start scheduler (future)

### Memory Layout

```
0x40000000 - Kernel code (.text)
           - Read-only data (.rodata)
           - Initialized data (.data)
           - BSS (zero-initialized)
           - Stack (16KB)
           - Heap (future)
```

### Key Subsystems (Planned)

- [ ] Device tree parser
- [ ] UART driver (serial debugging)
- [ ] Framebuffer driver (display output)
- [ ] GIC (Generic Interrupt Controller)
- [ ] Memory management (MMU, page tables)
- [ ] Exception/interrupt handling
- [ ] Basic scheduler
- [ ] Syscall interface

## Testing

### QEMU

The kernel can be tested in QEMU's ARM64 virt machine:

```bash
make run
```

Note: QEMU's virt machine is different from real iPhone 7 hardware.
Some drivers will need adaptation for real hardware.

### Real Hardware

⚠️ **WARNING**: Testing on real iPhone 7 requires:
- checkra1n jailbreak installed
- Custom bootchain setup
- Serial debug cable (optional but recommended)
- Risk of bricking device

(Detailed real hardware testing guide TBD)

## Resources

### ARM64 Documentation

- [ARM Architecture Reference Manual (ARMv8-A)](https://developer.arm.com/documentation)
- [ARM Cortex-A Series Programmer's Guide](https://developer.arm.com/documentation)
- [ARMv8-A Exception Handling](https://developer.arm.com/documentation)

### iPhone 7 Specific

- [checkra1n](https://checkra.in/) - Jailbreak tool
- [Project Sandcastle](https://projectsandcastle.org/) - Android on iPhone reference
- [iPhone Wiki](https://www.theiphonewiki.com/wiki/IPhone_7)

### Odin Language

- [Odin Language Documentation](https://odin-lang.org/docs/)
- [Odin GitHub](https://github.com/odin-lang/Odin)

## Contributing

This is a learning project. Contributions welcome!

Areas that need work:
- Device tree parser
- UART driver implementation
- MMU/page table setup
- Exception vector implementation
- Real hardware testing

## License

TBD

## Acknowledgments

- Odin programming language team
- checkra1n team for boot exploit
- ARM Ltd. for comprehensive documentation
- OSDev community for bare-metal development resources
