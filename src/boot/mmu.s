/*
 * OdinOS MMU Assembly - ARM64
 * Target: Apple iPhone 7 (A10 Fusion) - ARMv8-A
 *
 * Functions to configure and enable the ARM64 MMU
 */

.section .text

// Configure MAIR_EL1 (Memory Attribute Indirection Register)
// Sets up memory types for Normal and Device memory
.global mmu_configure_mair
mmu_configure_mair:
    // MAIR_EL1 format: 8 attribute bytes (Attr0-Attr7)
    // We'll use:
    //   Attr0 (index 0): Normal memory, write-back cacheable
    //   Attr1 (index 1): Device memory, nGnRnE (strongly ordered)
    //
    // Attr0 = 0xFF: Normal, Inner/Outer Write-Back cacheable, R/W allocate
    // Attr1 = 0x00: Device-nGnRnE (non-Gathering, non-Reordering, no Early ack)

    mov     x0, #0xFF                    // Attr0: Normal memory
    mov     x1, #0x00                    // Attr1: Device memory
    orr     x0, x0, x1, lsl #8           // Combine into MAIR
    msr     mair_el1, x0
    isb
    ret

// Configure TCR_EL1 (Translation Control Register)
// Sets up translation table parameters
.global mmu_configure_tcr
mmu_configure_tcr:
    // TCR_EL1 configuration for 4KB granule, 48-bit VA
    // T0SZ  = 16 (64 - 16 = 48-bit address space)
    // TG0   = 0  (4KB granule) - default, no need to set
    // SH0   = 3  (Inner shareable)
    // ORGN0 = 1  (Outer write-back cacheable)
    // IRGN0 = 1  (Inner write-back cacheable)
    // IPS   = 0  (32-bit physical address space) - default

    mov     x0, #16                      // T0SZ = 16 (48-bit VA)
    // TG0 = 0 is default, skip
    orr     x0, x0, #(3 << 12)           // SH0 = 3 (Inner shareable)
    orr     x0, x0, #(1 << 10)           // ORGN0 = 1 (Outer write-back)
    orr     x0, x0, #(1 << 8)            // IRGN0 = 1 (Inner write-back)
    // IPS = 0 is default, skip

    msr     tcr_el1, x0
    isb
    ret

// Set translation table base register
// x0 = physical address of level 0 page table
.global mmu_set_ttbr0
mmu_set_ttbr0:
    msr     ttbr0_el1, x0
    isb
    ret

// Enable the MMU
.global mmu_enable
mmu_enable:
    // Invalidate instruction cache
    ic      iallu
    dsb     sy

    // Invalidate TLB
    tlbi    vmalle1
    dsb     sy
    isb

    // Read SCTLR_EL1
    mrs     x0, sctlr_el1

    // Set M bit (bit 0) to enable MMU
    orr     x0, x0, #1

    // Set C bit (bit 2) to enable data cache
    orr     x0, x0, #(1 << 2)

    // Set I bit (bit 12) to enable instruction cache
    orr     x0, x0, #(1 << 12)

    // Write back to SCTLR_EL1
    msr     sctlr_el1, x0
    dsb     sy
    isb

    ret

// Disable the MMU (for debugging)
.global mmu_disable
mmu_disable:
    mrs     x0, sctlr_el1
    bic     x0, x0, #1                   // Clear M bit
    msr     sctlr_el1, x0
    dsb     sy
    isb
    ret
