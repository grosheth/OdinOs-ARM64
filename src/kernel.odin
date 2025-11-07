package kernel

// OdinOS - Main kernel entry point
// Target: Apple iPhone 7 (A10 Fusion) - ARMv8-A
//
// This is called from boot.s after initial CPU setup.
// At this point:
//  - Stack is set up
//  - BSS is zeroed
//  - We're in EL1 (or EL2)

// QEMU virt machine UART address (fallback if device tree parsing fails)
QEMU_UART_BASE :: 0x09000000

// Kernel entry point - called from boot assembly
// dt_addr: Device tree address passed by bootloader in x0
// Must use C calling convention for ARM64 AAPCS64
@(export, link_name="kernel_main")
kernel_main :: proc "c" (dt_addr: uintptr) {
    // Phase 1: Initialize UART for debugging
    // First try to get UART address from device tree, fallback to QEMU address
    uart_base := uintptr(0)

    // Try device tree first if address is provided
    if dt_addr != 0 {
        // Initialize temporary UART with QEMU address for debug output during DT parsing
        uart_init(QEMU_UART_BASE)

        kprintln("========================================")
        kprintln("   OdinOS ARM64 v0.2")
        kprintln("   Target: Apple iPhone 7 (A10 Fusion)")
        kprintln("========================================")
        kprint("\n")

        kprint("[1/5] Device tree address: ")
        print_hex64(u64(dt_addr))
        kprintln("")

        // Parse device tree
        if fdt_init(dt_addr) {
            kprintln("[2/5] Device tree initialized successfully")

            // Find UART in device tree
            uart_base = fdt_find_uart()

            if uart_base != 0 {
                kprint("[2/5] Found UART at ")
                print_hex64(u64(uart_base))
                kprintln("")

                // Re-initialize UART with discovered address
                uart_init(uart_base)
                kprintln("[2/5] UART re-initialized with device tree address")
            } else {
                kprintln("[2/5] WARNING: UART not found in device tree, using QEMU default")
                uart_base = QEMU_UART_BASE
            }
        } else {
            kprintln("[2/5] WARNING: Device tree parsing failed, using QEMU default")
            uart_base = QEMU_UART_BASE
        }
    } else {
        // No device tree address provided
        uart_base = QEMU_UART_BASE
        uart_init(uart_base)

        kprintln("========================================")
        kprintln("   OdinOS ARM64 v0.2")
        kprintln("   Target: Apple iPhone 7 (A10 Fusion)")
        kprintln("========================================")
        kprint("\n")

        kprintln("[1/5] UART initialized (QEMU default)")
        kprintln("[2/5] No device tree provided")
    }

    // Phase 3: Install exception vectors
    kprint("[3/5] Installing exception vectors...")
    install_exception_vectors()
    kprintln(" done")

    // Phase 4: Enable MMU and page tables
    kprintln("[4/5] Setting up MMU and page tables")
    mmu_init()
    kprintln("[4/5] MMU enabled successfully!")

    kprint("\n")
    kprintln("OdinOS boot complete!")
    kprint("\n")

    // Phase 5: Start interactive shell
    shell_init()
    shell_run()

    // Shell only returns if something goes very wrong
    // Fall back to halt loop
    kprintln("ERROR: Shell exited unexpectedly")
    for {
        arm_wfe()
    }
}

// ARM Wait For Event instruction - puts CPU in low power state
// Implemented in src/boot/wfe.s - executes the WFE instruction
// which puts the CPU into low-power mode until an interrupt/event occurs
foreign {
    @(link_name="arm_wfe")
    arm_wfe :: proc "c" () ---
}
