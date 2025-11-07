/*
 * OdinOS Exception Vector Table - ARM64
 * Target: Apple iPhone 7 (A10 Fusion) - ARMv8-A
 *
 * ARM64 requires a 2KB-aligned exception vector table with 16 vectors.
 * Each vector entry is 128 bytes (0x80), giving 16 × 128 = 2048 bytes total.
 *
 * Vector Table Layout:
 * 0x000-0x07F: Current EL with SP0 (using SP_EL0)
 * 0x080-0x0FF: IRQ for Current EL with SP0
 * 0x100-0x17F: FIQ for Current EL with SP0
 * 0x180-0x1FF: SError for Current EL with SP0
 *
 * 0x200-0x27F: Sync exception for Current EL with SPx (using SP_ELx)
 * 0x280-0x2FF: IRQ for Current EL with SPx
 * 0x300-0x37F: FIQ for Current EL with SPx
 * 0x380-0x3FF: SError for Current EL with SPx
 *
 * 0x400-0x47F: Sync exception from lower EL (AArch64)
 * 0x480-0x4FF: IRQ from lower EL (AArch64)
 * 0x500-0x57F: FIQ from lower EL (AArch64)
 * 0x580-0x5FF: SError from lower EL (AArch64)
 *
 * 0x600-0x67F: Sync exception from lower EL (AArch32)
 * 0x680-0x6FF: IRQ from lower EL (AArch32)
 * 0x700-0x77F: FIQ from lower EL (AArch32)
 * 0x780-0x7FF: SError from lower EL (AArch32)
 */

.section .text

// Macro to save exception context
// Saves all general purpose registers and important system registers
.macro exception_entry
    // Save general purpose registers x0-x30
    stp     x0, x1, [sp, #-16]!
    stp     x2, x3, [sp, #-16]!
    stp     x4, x5, [sp, #-16]!
    stp     x6, x7, [sp, #-16]!
    stp     x8, x9, [sp, #-16]!
    stp     x10, x11, [sp, #-16]!
    stp     x12, x13, [sp, #-16]!
    stp     x14, x15, [sp, #-16]!
    stp     x16, x17, [sp, #-16]!
    stp     x18, x19, [sp, #-16]!
    stp     x20, x21, [sp, #-16]!
    stp     x22, x23, [sp, #-16]!
    stp     x24, x25, [sp, #-16]!
    stp     x26, x27, [sp, #-16]!
    stp     x28, x29, [sp, #-16]!

    // Save x30 (link register) and exception link register
    mrs     x0, elr_el1
    mrs     x1, spsr_el1
    stp     x30, x0, [sp, #-16]!
    str     x1, [sp, #-8]!
.endm

// Macro to restore exception context
.macro exception_exit
    // Restore SPSR and ELR
    ldr     x1, [sp], #8
    ldp     x30, x0, [sp], #16
    msr     spsr_el1, x1
    msr     elr_el1, x0

    // Restore general purpose registers
    ldp     x28, x29, [sp], #16
    ldp     x26, x27, [sp], #16
    ldp     x24, x25, [sp], #16
    ldp     x22, x23, [sp], #16
    ldp     x20, x21, [sp], #16
    ldp     x18, x19, [sp], #16
    ldp     x16, x17, [sp], #16
    ldp     x14, x15, [sp], #16
    ldp     x12, x13, [sp], #16
    ldp     x10, x11, [sp], #16
    ldp     x8, x9, [sp], #16
    ldp     x6, x7, [sp], #16
    ldp     x4, x5, [sp], #16
    ldp     x2, x3, [sp], #16
    ldp     x0, x1, [sp], #16

    eret
.endm

// Macro to create a vector entry that calls a handler
.macro vector_entry label, handler
    .align 7  // Each vector is 128 bytes (2^7)
\label:
    exception_entry
    bl      \handler
    exception_exit
.endm

// The exception vector table
// Must be 2KB (0x800) aligned
.align 11
.global exception_vectors
exception_vectors:
    // Current EL with SP0
    vector_entry sync_el1_sp0, handle_sync_el1_sp0
    vector_entry irq_el1_sp0, handle_irq_el1_sp0
    vector_entry fiq_el1_sp0, handle_fiq_el1_sp0
    vector_entry serror_el1_sp0, handle_serror_el1_sp0

    // Current EL with SPx
    vector_entry sync_el1_spx, handle_sync_el1_spx
    vector_entry irq_el1_spx, handle_irq_el1_spx
    vector_entry fiq_el1_spx, handle_fiq_el1_spx
    vector_entry serror_el1_spx, handle_serror_el1_spx

    // Lower EL (AArch64)
    vector_entry sync_el0_64, handle_sync_el0_64
    vector_entry irq_el0_64, handle_irq_el0_64
    vector_entry fiq_el0_64, handle_fiq_el0_64
    vector_entry serror_el0_64, handle_serror_el0_64

    // Lower EL (AArch32)
    vector_entry sync_el0_32, handle_sync_el0_32
    vector_entry irq_el0_32, handle_irq_el0_32
    vector_entry fiq_el0_32, handle_fiq_el0_32
    vector_entry serror_el0_32, handle_serror_el0_32

// Function to install exception vectors
// Sets VBAR_EL1 to point to our vector table
.global install_exception_vectors
install_exception_vectors:
    adr     x0, exception_vectors
    msr     vbar_el1, x0
    isb
    ret
