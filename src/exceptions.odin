package kernel

// Exception Handlers for OdinOS
//
// These are called from the exception vector table in exceptions.s
// Each handler receives the saved CPU context on the stack

// Exception handlers for Current EL with SP0
@(export, link_name="handle_sync_el1_sp0")
handle_sync_el1_sp0 :: proc "c" () {
    kprintln("\n!!! EXCEPTION: Synchronous (EL1 SP0) !!!")
    exception_hang()
}

@(export, link_name="handle_irq_el1_sp0")
handle_irq_el1_sp0 :: proc "c" () {
    kprintln("\n!!! EXCEPTION: IRQ (EL1 SP0) !!!")
    exception_hang()
}

@(export, link_name="handle_fiq_el1_sp0")
handle_fiq_el1_sp0 :: proc "c" () {
    kprintln("\n!!! EXCEPTION: FIQ (EL1 SP0) !!!")
    exception_hang()
}

@(export, link_name="handle_serror_el1_sp0")
handle_serror_el1_sp0 :: proc "c" () {
    kprintln("\n!!! EXCEPTION: SError (EL1 SP0) !!!")
    exception_hang()
}

// Exception handlers for Current EL with SPx
@(export, link_name="handle_sync_el1_spx")
handle_sync_el1_spx :: proc "c" () {
    kprintln("\n!!! EXCEPTION: Synchronous (EL1 SPx) !!!")
    kprint("This is likely a kernel fault!\n")
    exception_hang()
}

@(export, link_name="handle_irq_el1_spx")
handle_irq_el1_spx :: proc "c" () {
    // IRQ handler - reads interrupt ID from GIC and dispatches to handler

    // Step 1: Acknowledge the interrupt (read IAR)
    irq := gic_acknowledge_interrupt()

    // Step 2: Dispatch to registered handler
    if irq != GIC_IRQ_SPURIOUS {
        irq_dispatch(irq)
    }

    // Step 3: Signal end of interrupt
    gic_end_of_interrupt(irq)
}

@(export, link_name="handle_fiq_el1_spx")
handle_fiq_el1_spx :: proc "c" () {
    // FIQ handler - similar to IRQ but for fast interrupts
    // In GICv2, FIQs are rarely used (most interrupts go through IRQ)

    // Acknowledge the interrupt
    irq := gic_acknowledge_interrupt()

    // Dispatch to handler
    if irq != GIC_IRQ_SPURIOUS {
        irq_dispatch(irq)
    }

    // Signal end of interrupt
    gic_end_of_interrupt(irq)
}

@(export, link_name="handle_serror_el1_spx")
handle_serror_el1_spx :: proc "c" () {
    kprintln("\n!!! EXCEPTION: SError (EL1 SPx) !!!")
    kprint("This indicates a serious hardware error!\n")
    exception_hang()
}

// Exception handlers for Lower EL (AArch64)
@(export, link_name="handle_sync_el0_64")
handle_sync_el0_64 :: proc "c" () {
    kprintln("\n!!! EXCEPTION: Synchronous (EL0 64-bit) !!!")
    kprint("User mode exception (not yet implemented)\n")
    exception_hang()
}

@(export, link_name="handle_irq_el0_64")
handle_irq_el0_64 :: proc "c" () {
    kprintln("\n>>> IRQ received (EL0 64-bit)")
    // TODO: Handle user mode IRQ
}

@(export, link_name="handle_fiq_el0_64")
handle_fiq_el0_64 :: proc "c" () {
    kprintln("\n!!! EXCEPTION: FIQ (EL0 64-bit) !!!")
    exception_hang()
}

@(export, link_name="handle_serror_el0_64")
handle_serror_el0_64 :: proc "c" () {
    kprintln("\n!!! EXCEPTION: SError (EL0 64-bit) !!!")
    exception_hang()
}

// Exception handlers for Lower EL (AArch32)
@(export, link_name="handle_sync_el0_32")
handle_sync_el0_32 :: proc "c" () {
    kprintln("\n!!! EXCEPTION: Synchronous (EL0 32-bit) !!!")
    kprint("32-bit user mode not supported\n")
    exception_hang()
}

@(export, link_name="handle_irq_el0_32")
handle_irq_el0_32 :: proc "c" () {
    kprintln("\n!!! EXCEPTION: IRQ (EL0 32-bit) !!!")
    exception_hang()
}

@(export, link_name="handle_fiq_el0_32")
handle_fiq_el0_32 :: proc "c" () {
    kprintln("\n!!! EXCEPTION: FIQ (EL0 32-bit) !!!")
    exception_hang()
}

@(export, link_name="handle_serror_el0_32")
handle_serror_el0_32 :: proc "c" () {
    kprintln("\n!!! EXCEPTION: SError (EL0 32-bit) !!!")
    exception_hang()
}

// Hang the system after a fatal exception
exception_hang :: proc "c" () {
    kprintln("!!! SYSTEM HALTED DUE TO EXCEPTION !!!")
    kprint("\n")

    // Disable interrupts and halt
    for {
        // Wait for event - low power halt
        arm_wfe()
    }
}

// Function declarations for assembly routines
foreign {
    @(link_name="install_exception_vectors")
    install_exception_vectors :: proc "c" () ---
}
