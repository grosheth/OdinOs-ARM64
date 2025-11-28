package kernel

// ARM Generic Interrupt Controller (GIC) Driver
//
// Implements GICv2 architecture for interrupt handling on ARM Cortex-A processors.
// GICv2 consists of two main components:
//   - Distributor (GICD): Global interrupt configuration and distribution
//   - CPU Interface (GICC): Per-CPU interrupt handling
//
// References:
//   - ARM Generic Interrupt Controller Architecture Specification v2.0
//   - ARM Cortex-A Series Programmer's Guide
//   - QEMU virt machine uses GICv2 at 0x08000000 (GICD) and 0x08010000 (GICC)

// ============================================================================
// GIC Distributor (GICD) Register Offsets
// ============================================================================

GICD_CTLR       :: 0x000  // Distributor Control Register
GICD_TYPER      :: 0x004  // Interrupt Controller Type Register
GICD_IIDR       :: 0x008  // Distributor Implementer Identification Register
GICD_IGROUPR    :: 0x080  // Interrupt Group Registers (32 bits per reg, 1 bit per IRQ)
GICD_ISENABLER  :: 0x100  // Interrupt Set-Enable Registers (32 bits per reg, 1 bit per IRQ)
GICD_ICENABLER  :: 0x180  // Interrupt Clear-Enable Registers
GICD_ISPENDR    :: 0x200  // Interrupt Set-Pending Registers
GICD_ICPENDR    :: 0x280  // Interrupt Clear-Pending Registers
GICD_ISACTIVER  :: 0x300  // Interrupt Set-Active Registers
GICD_ICACTIVER  :: 0x380  // Interrupt Clear-Active Registers
GICD_IPRIORITYR :: 0x400  // Interrupt Priority Registers (8 bits per IRQ)
GICD_ITARGETSR  :: 0x800  // Interrupt Processor Targets Registers (8 bits per IRQ)
GICD_ICFGR      :: 0xC00  // Interrupt Configuration Registers (2 bits per IRQ)
GICD_SGIR       :: 0xF00  // Software Generated Interrupt Register

// ============================================================================
// GIC CPU Interface (GICC) Register Offsets
// ============================================================================

GICC_CTLR       :: 0x0000  // CPU Interface Control Register
GICC_PMR        :: 0x0004  // Interrupt Priority Mask Register
GICC_BPR        :: 0x0008  // Binary Point Register
GICC_IAR        :: 0x000C  // Interrupt Acknowledge Register
GICC_EOIR       :: 0x0010  // End of Interrupt Register
GICC_RPR        :: 0x0014  // Running Priority Register
GICC_HPPIR      :: 0x0018  // Highest Priority Pending Interrupt Register
GICC_ABPR       :: 0x001C  // Aliased Binary Point Register
GICC_AIAR       :: 0x0020  // Aliased Interrupt Acknowledge Register
GICC_AEOIR      :: 0x0024  // Aliased End of Interrupt Register
GICC_AHPPIR     :: 0x0028  // Aliased Highest Priority Pending Interrupt Register
GICC_APR0       :: 0x00D0  // Active Priorities Register 0
GICC_NSAPR0     :: 0x00E0  // Non-secure Active Priorities Register 0
GICC_IIDR       :: 0x00FC  // CPU Interface Identification Register
GICC_DIR        :: 0x1000  // Deactivate Interrupt Register

// ============================================================================
// GIC Register Bit Definitions
// ============================================================================

// GICD_CTLR bits
GICD_CTLR_ENABLE :: 0x1  // Enable distributor

// GICC_CTLR bits
GICC_CTLR_ENABLE :: 0x1  // Enable CPU interface

// GICD_ICFGR bits (2 bits per interrupt)
GICD_ICFGR_LEVEL :: 0x0  // Level-sensitive
GICD_ICFGR_EDGE  :: 0x2  // Edge-triggered

// Special interrupt IDs
GIC_IRQ_SPURIOUS :: 1023  // Spurious interrupt (no pending interrupt)

// Maximum number of interrupts (GICv2 supports up to 1020, typically 0-1019)
GIC_MAX_IRQS :: 1020

// ============================================================================
// GIC State
// ============================================================================

gic_distributor_base: uintptr = 0
gic_cpu_interface_base: uintptr = 0
gic_num_interrupts: u32 = 0
gic_initialized: bool = false

// ============================================================================
// GIC Initialization
// ============================================================================

// Initialize the GIC (must be called after device tree parsing and MMU setup)
gic_init :: proc "c" (gicd_base: uintptr, gicc_base: uintptr) -> bool {
    if gicd_base == 0 || gicc_base == 0 {
        kprintln("ERROR: Invalid GIC base addresses")
        return false
    }

    gic_distributor_base = gicd_base
    gic_cpu_interface_base = gicc_base

    kprintln("Initializing GIC...")
    kprint("  GICD base: ")
    print_hex64(u64(gicd_base))
    kprintln("")
    kprint("  GICC base: ")
    print_hex64(u64(gicc_base))
    kprintln("")

    // Step 1: Disable the distributor before configuration
    mmio_write_u32(gicd_base + GICD_CTLR, 0)

    // Step 2: Read the number of interrupt lines
    // GICD_TYPER[4:0] = ITLinesNumber
    // Number of interrupts = 32 * (ITLinesNumber + 1)
    typer := mmio_read_u32(gicd_base + GICD_TYPER)
    it_lines_number := typer & 0x1F
    gic_num_interrupts = 32 * (it_lines_number + 1)

    kprint("  Number of interrupt lines: ")
    print_hex32(gic_num_interrupts)
    kprintln("")

    // Step 3: Disable all interrupts
    // Each GICD_ICENABLER register controls 32 interrupts
    num_regs := (gic_num_interrupts + 31) / 32
    for i: u32 = 0; i < num_regs; i += 1 {
        mmio_write_u32(gicd_base + GICD_ICENABLER + uintptr(i * 4), 0xFFFFFFFF)
    }

    // Step 4: Clear all pending interrupts
    for i: u32 = 0; i < num_regs; i += 1 {
        mmio_write_u32(gicd_base + GICD_ICPENDR + uintptr(i * 4), 0xFFFFFFFF)
    }

    // Step 5: Set all interrupts to lowest priority (0xFF = lowest)
    // Each GICD_IPRIORITYR register controls 4 interrupts (8 bits each)
    num_priority_regs := (gic_num_interrupts + 3) / 4
    for i: u32 = 0; i < num_priority_regs; i += 1 {
        mmio_write_u32(gicd_base + GICD_IPRIORITYR + uintptr(i * 4), 0xFFFFFFFF)
    }

    // Step 6: Target all interrupts to CPU0
    // Each GICD_ITARGETSR register controls 4 interrupts (8 bits each)
    // CPU0 = 0x01 in each byte
    num_target_regs := (gic_num_interrupts + 3) / 4
    for i: u32 = 0; i < num_target_regs; i += 1 {
        mmio_write_u32(gicd_base + GICD_ITARGETSR + uintptr(i * 4), 0x01010101)
    }

    // Step 7: Configure all interrupts as level-sensitive (not edge-triggered)
    // Each GICD_ICFGR register controls 16 interrupts (2 bits each)
    // 0 = level-sensitive, 2 = edge-triggered
    num_cfg_regs := (gic_num_interrupts + 15) / 16
    for i: u32 = 0; i < num_cfg_regs; i += 1 {
        mmio_write_u32(gicd_base + GICD_ICFGR + uintptr(i * 4), 0x00000000)
    }

    // Step 8: Enable distributor
    mmio_write_u32(gicd_base + GICD_CTLR, GICD_CTLR_ENABLE)

    // Step 9: Configure CPU interface
    // Set priority mask to allow all interrupts (0xFF = all priorities)
    mmio_write_u32(gicc_base + GICC_PMR, 0xFF)

    // Set binary point to 0 (all 8 bits used for priority)
    mmio_write_u32(gicc_base + GICC_BPR, 0)

    // Step 10: Enable CPU interface
    mmio_write_u32(gicc_base + GICC_CTLR, GICC_CTLR_ENABLE)

    gic_initialized = true
    kprintln("GIC initialization complete")

    return true
}

// ============================================================================
// Interrupt Enable/Disable
// ============================================================================

// Enable a specific interrupt number
gic_enable_interrupt :: proc "c" (irq: u32) {
    if !gic_initialized || irq >= gic_num_interrupts {
        return
    }

    // Each bit in GICD_ISENABLER controls one interrupt
    reg_idx := irq / 32
    bit_idx := irq % 32

    mmio_write_u32(gic_distributor_base + GICD_ISENABLER + uintptr(reg_idx * 4),
                   u32(1) << bit_idx)
}

// Disable a specific interrupt number
gic_disable_interrupt :: proc "c" (irq: u32) {
    if !gic_initialized || irq >= gic_num_interrupts {
        return
    }

    reg_idx := irq / 32
    bit_idx := irq % 32

    mmio_write_u32(gic_distributor_base + GICD_ICENABLER + uintptr(reg_idx * 4),
                   u32(1) << bit_idx)
}

// Set interrupt priority (0 = highest, 255 = lowest)
gic_set_priority :: proc "c" (irq: u32, priority: u8) {
    if !gic_initialized || irq >= gic_num_interrupts {
        return
    }

    // Each GICD_IPRIORITYR register holds 4 priorities (8 bits each)
    reg_idx := irq / 4
    byte_idx := irq % 4

    reg_addr := gic_distributor_base + GICD_IPRIORITYR + uintptr(reg_idx * 4)
    current := mmio_read_u32(reg_addr)

    // Clear the old priority and set the new one
    shift := byte_idx * 8
    mask := u32(0xFF) << shift
    current = (current & ~mask) | (u32(priority) << shift)

    mmio_write_u32(reg_addr, current)
}

// ============================================================================
// Interrupt Acknowledge and End of Interrupt
// ============================================================================

// Acknowledge an interrupt (called by IRQ handler)
// Returns the interrupt ID, or GIC_IRQ_SPURIOUS if no interrupt pending
// HOT PATH: Called on every interrupt, compiler will inline with -o:speed
gic_acknowledge_interrupt :: proc "c" () -> u32 {
    if !gic_initialized {
        return GIC_IRQ_SPURIOUS
    }

    // Read IAR to get the interrupt ID and acknowledge it
    irq := mmio_read_u32(gic_cpu_interface_base + GICC_IAR)
    return irq
}

// Signal end of interrupt handling (called after IRQ handler completes)
// HOT PATH: Called on every interrupt, compiler will inline with -o:speed
gic_end_of_interrupt :: proc "c" (irq: u32) {
    if !gic_initialized {
        return
    }

    // Write the interrupt ID to EOIR to signal completion
    mmio_write_u32(gic_cpu_interface_base + GICC_EOIR, irq)
}
