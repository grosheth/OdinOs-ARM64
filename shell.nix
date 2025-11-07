{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  name = "odinos-arm64-dev";

  buildInputs = with pkgs; [
    # Odin compiler
    odin

    # ARM64 cross-compilation toolchain
    gcc_multi
    pkgsCross.aarch64-multiplatform.buildPackages.gcc
    pkgsCross.aarch64-multiplatform.buildPackages.binutils

    # QEMU for ARM64 emulation
    qemu

    # Debugging tools
    pkgsCross.aarch64-multiplatform.buildPackages.gdb

    # Device tree tools (for parsing iPhone device trees)
    dtc

    # Build tools
    gnumake
    cmake

    # Analysis and inspection tools
    hexdump
    xxd
    file

    # Version control
    git

    # Text editor helpers
    clang-tools  # For clangd LSP if using with editor
  ];

  shellHook = ''
    echo "================================================"
    echo "OdinOS ARM64 Development Environment (iPhone 7)"
    echo "================================================"
    echo ""
    echo "Available tools:"
    echo "  - odin: Odin compiler"
    echo "  - aarch64-unknown-linux-gnu-gcc: ARM64 GCC"
    echo "  - aarch64-unknown-linux-gnu-ld: ARM64 linker"
    echo "  - qemu-system-aarch64: ARM64 QEMU emulator"
    echo "  - gdb: ARM64 debugger"
    echo "  - dtc: Device tree compiler"
    echo ""
    echo "Quick start:"
    echo "  1. Create your kernel code in src/"
    echo "  2. Build with: make"
    echo "  3. Test with: qemu-system-aarch64 (see Makefile)"
    echo ""
    echo "Target: Apple iPhone 7 (A10 Fusion / ARMv8-A)"
    echo "================================================"

    # Set up environment variables
    export CROSS_COMPILE=aarch64-unknown-linux-gnu-
    export ARCH=arm64
    export TARGET=aarch64

    # Add current directory to path for local scripts
    export PATH="$PWD/scripts:$PATH"
  '';
}
