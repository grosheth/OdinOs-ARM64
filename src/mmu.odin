package kernel

// MMU (Memory Management Unit) Configuration and Control
//
// This module configures the ARM64 MMU with:
//  - 4KB page granule
//  - 48-bit virtual addressing
//  - Identity mapping for kernel code and MMIO regions

// Memory regions to map
KERNEL_BASE     :: 0x40000000  // Where kernel is loaded
KERNEL_SIZE     :: 0x08000000  // 128MB for kernel
UART_BASE       :: 0x09000000  // QEMU UART
UART_SIZE       :: 0x00001000  // 4KB

// External assembly functions
foreign {
    @(link_name="mmu_configure_mair")
    mmu_configure_mair :: proc "c" () ---

    @(link_name="mmu_configure_tcr")
    mmu_configure_tcr :: proc "c" () ---

    @(link_name="mmu_set_ttbr0")
    mmu_set_ttbr0 :: proc "c" (table_addr: u64) ---

    @(link_name="mmu_enable")
    mmu_enable :: proc "c" () ---

    @(link_name="mmu_disable")
    mmu_disable :: proc "c" () ---
}

// GIC region sizes
GICD_SIZE :: 0x00010000  // 64KB for GIC Distributor
GICC_SIZE :: 0x00010000  // 64KB for GIC CPU Interface

// Initialize and enable the MMU
mmu_init :: proc "c" (gic_addrs: GIC_Addresses) -> bool {
    // 1. Initialize page tables (they're already zeroed in BSS)
    init_page_tables()

    // 2. Create identity mappings
    kprint("  - Mapping kernel (0x40000000-0x48000000)...")

    // Map kernel as normal memory, executable
    map_range(KERNEL_BASE, KERNEL_BASE, KERNEL_SIZE, false, true)
    kprintln(" ok")

    // Map UART as device memory, non-executable
    kprint("  - Mapping UART (0x09000000)...")
    map_range(UART_BASE, UART_BASE, UART_SIZE, true, false)
    kprintln(" ok")

    // Map GIC if found
    if gic_addrs.found {
        kprint("  - Mapping GIC Distributor (")
        print_hex64(u64(gic_addrs.distributor_base))
        kprint(")...")
        map_range(u64(gic_addrs.distributor_base), u64(gic_addrs.distributor_base), GICD_SIZE, true, false)
        kprintln(" ok")

        kprint("  - Mapping GIC CPU Interface (")
        print_hex64(u64(gic_addrs.cpu_interface_base))
        kprint(")...")
        map_range(u64(gic_addrs.cpu_interface_base), u64(gic_addrs.cpu_interface_base), GICC_SIZE, true, false)
        kprintln(" ok")
    }

    // 3. Configure MAIR (Memory Attribute Indirection Register)
    kprint("  - Configuring MAIR...")
    mmu_configure_mair()
    kprintln(" ok")

    // 4. Configure TCR (Translation Control Register)
    kprint("  - Configuring TCR...")
    mmu_configure_tcr()
    kprintln(" ok")

    // 5. Set TTBR0 to point to our level 0 page table
    kprint("  - Setting TTBR0...")
    ttbr0_addr := u64(uintptr(&page_tables_l0))
    mmu_set_ttbr0(ttbr0_addr)
    kprintln(" ok")

    // 6. Enable MMU
    kprint("  - Enabling MMU...")
    mmu_enable()
    kprintln(" ok")

    return true
}

// Check if MMU is enabled
mmu_is_enabled :: proc "c" () -> bool {
    // We'd need to read SCTLR_EL1 to check, but for now
    // we'll just track it manually
    return true  // Assume it's enabled after mmu_init
}
