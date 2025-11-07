/*
 * ARM Wait For Event (WFE) Implementation
 *
 * The WFE instruction puts the CPU into a low-power state until:
 *  - An interrupt occurs (IRQ/FIQ)
 *  - An event is signaled (SEV instruction)
 *  - A debug event occurs
 *
 * This is the ARM-recommended way to idle the CPU.
 * Critical for power efficiency on battery-powered devices like iPhone 7.
 */

.section .text
.global arm_wfe

// void arm_wfe(void)
// Wait for event - low power CPU idle
arm_wfe:
    wfe         // Wait for event instruction
    ret         // Return to caller
