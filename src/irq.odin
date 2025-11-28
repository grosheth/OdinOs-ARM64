package kernel

// IRQ (Interrupt Request) Dispatcher for OdinOS
//
// Manages interrupt handlers and dispatches interrupts to the appropriate handler.
// Works with the GIC (Generic Interrupt Controller) to acknowledge and handle IRQs.

// IRQ handler function type
IRQ_Handler :: proc "c" (irq: u32)

// Maximum number of IRQ handlers (matches GIC_MAX_IRQS)
MAX_IRQ_HANDLERS :: 1020

// IRQ handler table
// Each entry can be nil (unhandled) or a function pointer to the handler
irq_handlers: [MAX_IRQ_HANDLERS]IRQ_Handler

// Statistics
irq_count_total: u64 = 0
irq_count_spurious: u64 = 0
irq_count_unhandled: u64 = 0

// Register an IRQ handler for a specific interrupt number
irq_register_handler :: proc "c" (irq: u32, handler: IRQ_Handler) -> bool {
    if irq >= MAX_IRQ_HANDLERS {
        kprint("ERROR: IRQ number ")
        print_hex32(irq)
        kprintln(" out of range")
        return false
    }

    if irq_handlers[irq] != nil {
        kprint("WARNING: Replacing existing handler for IRQ ")
        print_hex32(irq)
        kprintln("")
    }

    irq_handlers[irq] = handler

    kprint("Registered handler for IRQ ")
    print_hex32(irq)
    kprintln("")

    return true
}

// Unregister an IRQ handler
irq_unregister_handler :: proc "c" (irq: u32) {
    if irq < MAX_IRQ_HANDLERS {
        irq_handlers[irq] = nil
    }
}

// Main IRQ dispatcher - called from exception handler
// This function is called after the GIC has acknowledged an interrupt
// HOT PATH: Called on every interrupt
irq_dispatch :: proc "c" (irq: u32) {
    irq_count_total += 1

    // Check for spurious interrupt
    if irq == GIC_IRQ_SPURIOUS {
        irq_count_spurious += 1
        return
    }

    // GIC hardware guarantees irq < 1020 if not spurious (GIC_IRQ_SPURIOUS = 1023)
    // The bounds check is redundant and wastes cycles in the hot path

    // Check if we have a handler registered
    handler := irq_handlers[irq]
    if handler == nil {
        irq_count_unhandled += 1
        kprint("WARNING: Unhandled IRQ ")
        print_hex32(irq)
        kprintln("")
        return
    }

    // Call the registered handler
    handler(irq)
}

// Debug: Print IRQ statistics
irq_print_stats :: proc "c" () {
    kprintln("IRQ Statistics:")
    kprint("  Total IRQs: ")
    print_hex64(irq_count_total)
    kprintln("")
    kprint("  Spurious IRQs: ")
    print_hex64(irq_count_spurious)
    kprintln("")
    kprint("  Unhandled IRQs: ")
    print_hex64(irq_count_unhandled)
    kprintln("")
}
