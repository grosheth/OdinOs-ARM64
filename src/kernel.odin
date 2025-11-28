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
    uart_irq_num: u32 = 0

    // Try device tree first if address is provided
    if dt_addr != 0 {
        // Initialize temporary UART with QEMU address for debug output during DT parsing
        uart_init(QEMU_UART_BASE)

        kprintln("========================================")
        kprintln("   OdinOS ARM64 v0.4.1")
        kprintln("   Target: Apple iPhone 7 (A10 Fusion)")
        kprintln("========================================")
        kprint("\n")

        kprint("[1/7] Device tree address: ")
        print_hex64(u64(dt_addr))
        kprintln("")

        // Parse device tree
        if fdt_init(dt_addr) {
            kprintln("[2/7] Device tree initialized successfully")

            // Find UART in device tree (with IRQ)
            uart_info := fdt_find_uart_full()

            if uart_info.found {
                uart_base = uart_info.base_address
                uart_irq_num = uart_info.irq_number

                // Re-initialize UART with discovered address
                uart_init(uart_base)
                kprintln("[2/7] UART re-initialized with device tree address")
            } else {
                kprintln("[2/7] WARNING: UART not found in device tree, using QEMU default")
                uart_base = QEMU_UART_BASE
            }
        } else {
            kprintln("[2/7] WARNING: Device tree parsing failed, using QEMU default")
            uart_base = QEMU_UART_BASE
        }
    } else {
        // No device tree address provided
        uart_base = QEMU_UART_BASE
        uart_init(uart_base)

        kprintln("========================================")
        kprintln("   OdinOS ARM64 v0.4.1")
        kprintln("   Target: Apple iPhone 7 (A10 Fusion)")
        kprintln("========================================")
        kprint("\n")

        kprintln("[1/7] UART initialized (QEMU default)")
        kprintln("[2/7] No device tree provided")
    }

    // Phase 3: Discover GIC from device tree
    gic_addrs := GIC_Addresses{0, 0, false}
    if dt_addr != 0 {
        gic_addrs = fdt_find_gic()
        if gic_addrs.found {
            kprintln("[3/7] GIC discovered from device tree")
        } else {
            kprintln("[3/7] WARNING: GIC not found in device tree")
        }
    } else {
        kprintln("[3/7] No device tree - skipping GIC discovery")
    }

    // Phase 4: Install exception vectors
    kprint("[4/7] Installing exception vectors...")
    install_exception_vectors()
    kprintln(" done")

    // Phase 5: Enable MMU and page tables (with GIC mapping if found)
    kprintln("[5/7] Setting up MMU and page tables")
    mmu_init(gic_addrs)
    kprintln("[5/7] MMU enabled successfully!")

    // Phase 6: Initialize GIC if found
    if gic_addrs.found {
        kprintln("[6/7] Initializing GIC...")
        if gic_init(gic_addrs.distributor_base, gic_addrs.cpu_interface_base) {
            kprintln("[6/7] GIC initialized successfully!")
        } else {
            kprintln("[6/7] ERROR: GIC initialization failed")
        }
    }

    // Phase 7: Enable UART interrupts if we have both GIC and UART IRQ
    if gic_addrs.found && uart_irq_num != 0 {
        kprintln("[7/7] Enabling UART RX interrupts...")
        uart_enable_rx_interrupt(uart_irq_num)
        kprintln("[7/7] UART interrupts enabled!")
    } else {
        if !gic_addrs.found {
            kprintln("[7/7] WARNING: No GIC - UART interrupts unavailable")
        } else {
            kprintln("[7/7] WARNING: No UART IRQ - UART interrupts unavailable")
        }
    }

    kprint("\n")
    kprintln("OdinOS boot complete!")
    kprint("\n")

    // Phase 8: Start interactive shell
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
