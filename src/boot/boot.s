/*
 * OdinOS Boot Assembly - ARM64
 * Target: Apple iPhone 7 (A10 Fusion) - ARMv8-A
 *
 * This is the kernel entry point. iBoot loads the kernel and jumps here.
 * We must:
 *  1. Check current Exception Level (EL1 or EL2)
 *  2. Set up the stack pointer
 *  3. Zero the BSS section
 *  4. Jump to kernel_main (Odin code)
 */

.section .text.boot
.global _start

_start:
    // IMPORTANT: x0 contains device tree address from bootloader
    // Save it before we modify x0
    mov     x20, x0             // Save device tree address in x20 (callee-saved)

    // Read CurrentEL register to determine exception level
    mrs     x0, CurrentEL
    and     x0, x0, #0xC        // Extract EL bits [3:2]
    cmp     x0, #8              // EL2 = 0b1000
    beq     from_el2
    cmp     x0, #4              // EL1 = 0b0100
    beq     from_el1

    // Unknown EL - halt
    b       halt

from_el2:
    // We're in EL2 (hypervisor mode)
    // For now, just continue - future: drop to EL1
    // TODO: Implement EL2 -> EL1 transition
    b       setup_stack

from_el1:
    // We're in EL1 (kernel mode) - perfect!
    b       setup_stack

setup_stack:
    // Set up stack pointer using linker-defined symbol
    ldr     x0, =__stack_top
    mov     sp, x0

zero_bss:
    // Zero out the BSS section
    ldr     x0, =__bss_start    // Start address
    ldr     x1, =__bss_end      // End address

zero_bss_loop:
    cmp     x0, x1              // Check if done
    bge     zero_bss_done       // If start >= end, done
    str     xzr, [x0], #8       // Store zero, increment by 8 bytes
    b       zero_bss_loop

zero_bss_done:
    // Jump to Odin kernel_main with device tree address in x0
    mov     x0, x20             // Restore device tree address to x0
    bl      kernel_main

    // If kernel_main returns (it shouldn't), halt
halt:
    wfe                         // Wait for event (low power)
    b       halt                // Infinite loop
