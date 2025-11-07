/*
 * Mask IRQ and FIQ interrupts at CPU level
 *
 * Sets the I and F bits in DAIF register to mask interrupts.
 * This prevents IRQ and FIQ exceptions from being taken.
 *
 * Needed for polled I/O mode when we don't have interrupt handlers.
 */

.section .text
.global mask_interrupts_asm

// void mask_interrupts_asm(void)
// Mask IRQ (I bit) and FIQ (F bit) in DAIF register
mask_interrupts_asm:
    msr daifset, #3     // Set I and F bits (mask IRQ and FIQ)
    isb                 // Ensure masking takes effect
    ret
