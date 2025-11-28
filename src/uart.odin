package kernel

import "base:intrinsics"

// UART Driver for ARM PL011
//
// Provides serial debugging output for OdinOS.
// Supports the ARM PL011 UART, which is used in:
//  - QEMU virt machine (at 0x09000000)
//  - Many ARM development boards
//  - Possibly iPhone 7 (or a compatible variant)
//
// This driver uses polled I/O (not interrupt-driven).

// PL011 UART Register Offsets
UART_DR     :: 0x00  // Data Register
UART_FR     :: 0x18  // Flag Register
UART_IBRD   :: 0x24  // Integer Baud Rate Divisor
UART_FBRD   :: 0x28  // Fractional Baud Rate Divisor
UART_LCRH   :: 0x2C  // Line Control Register
UART_CR     :: 0x30  // Control Register
UART_IMSC   :: 0x38  // Interrupt Mask Set/Clear
UART_ICR    :: 0x44  // Interrupt Clear Register

// Flag Register Bits
UART_FR_TXFF :: 0x20  // Transmit FIFO Full
UART_FR_RXFE :: 0x10  // Receive FIFO Empty
UART_FR_BUSY :: 0x08  // UART Busy

// Line Control Register Bits
UART_LCRH_WLEN_8BIT :: 0x60  // 8-bit word length
UART_LCRH_FEN       :: 0x10  // Enable FIFOs

// Control Register Bits
UART_CR_UARTEN :: 0x01    // UART Enable
UART_CR_TXE    :: 0x100   // Transmit Enable
UART_CR_RXE    :: 0x200   // Receive Enable

// Interrupt Mask Bits
UART_IMSC_RXIM :: 0x10    // Receive interrupt mask

// Interrupt Status Bits
UART_MIS       :: 0x40    // Masked Interrupt Status
UART_MIS_RXMIS :: 0x10    // Receive masked interrupt status

// Global UART base address (set by uart_init)
uart_base: uintptr = 0

// UART IRQ number (from device tree)
uart_irq: u32 = 0

// Circular buffer for received characters
// IMPORTANT: Buffer size MUST be power of 2 (256 = 2^8) for bitwise AND optimization
// This allows (index + 1) % 256 to be optimized to (index + 1) & 0xFF
//
// SECURITY: Head and tail are accessed atomically to prevent race conditions
// between the IRQ handler (producer) and shell (consumer)
UART_RX_BUFFER_SIZE :: 256
uart_rx_buffer: [UART_RX_BUFFER_SIZE]u8
uart_rx_head: u32 = 0  // Write position (modified by IRQ handler)
uart_rx_tail: u32 = 0  // Read position (modified by shell)

// Check if RX buffer has data
// SECURITY: Uses atomic loads to prevent race conditions
uart_rx_available :: proc "c" () -> bool {
    head := intrinsics.atomic_load_explicit(&uart_rx_head, .Acquire)
    tail := intrinsics.atomic_load_explicit(&uart_rx_tail, .Acquire)
    return head != tail
}

// Read from RX buffer (non-blocking)
// SECURITY: Uses atomic operations to prevent races with IRQ handler
uart_rx_read :: proc "c" () -> (u8, bool) {
    // Load head and tail atomically with acquire semantics
    head := intrinsics.atomic_load_explicit(&uart_rx_head, .Acquire)
    tail := intrinsics.atomic_load_explicit(&uart_rx_tail, .Acquire)

    if head == tail {
        return 0, false  // Buffer empty
    }

    // Read character from buffer
    c := uart_rx_buffer[tail]

    // Update tail atomically with release semantics
    new_tail := (tail + 1) & 0xFF
    intrinsics.atomic_store_explicit(&uart_rx_tail, new_tail, .Release)

    return c, true
}

// Write to RX buffer (called from IRQ handler)
// SECURITY: Uses atomic operations to prevent races with shell reader
uart_rx_write :: proc "c" (c: u8) {
    // Load head and tail atomically with acquire semantics
    head := intrinsics.atomic_load_explicit(&uart_rx_head, .Acquire)
    tail := intrinsics.atomic_load_explicit(&uart_rx_tail, .Acquire)

    next_head := (head + 1) & 0xFF

    if next_head == tail {
        // Buffer full, drop character
        return
    }

    // Write character to buffer
    uart_rx_buffer[head] = c

    // Update head atomically with release semantics
    intrinsics.atomic_store_explicit(&uart_rx_head, next_head, .Release)
}

// Initialize the UART
// base_addr: Physical address of the UART (e.g., 0x09000000 for QEMU)
uart_init :: proc "c" (base_addr: uintptr) {
    uart_base = base_addr

    // 1. Disable UART while configuring
    mmio_write_u32(uart_base + UART_CR, 0)

    // 2. Wait for current transmission to complete
    for (mmio_read_u32(uart_base + UART_FR) & UART_FR_BUSY) != 0 {
        // Busy wait
    }

    // 3. Flush the transmit FIFO by disabling FIFOs
    mmio_write_u32(uart_base + UART_LCRH, 0)

    // 4. Clear all interrupts
    mmio_write_u32(uart_base + UART_ICR, 0x7FF)

    // 5. Set baud rate to 115200
    // Assuming UART clock is 24MHz (common for QEMU and many ARM boards)
    // BAUDDIV = (24000000) / (16 * 115200) = 13.02
    // IBRD = 13
    // FBRD = int(0.02 * 64 + 0.5) = 1
    mmio_write_u32(uart_base + UART_IBRD, 13)
    mmio_write_u32(uart_base + UART_FBRD, 1)

    // 6. Set line control: 8 bits, no parity, 1 stop bit, enable FIFOs
    mmio_write_u32(uart_base + UART_LCRH, UART_LCRH_WLEN_8BIT | UART_LCRH_FEN)

    // 7. Disable interrupts (we're using polled I/O)
    mmio_write_u32(uart_base + UART_IMSC, 0)

    // 8. Enable UART, TX, and RX
    mmio_write_u32(uart_base + UART_CR, UART_CR_UARTEN | UART_CR_TXE | UART_CR_RXE)
}

// Transmit a single character
// Waits for TX FIFO to have space
@(optimization_mode="favor_size")
uart_putc :: proc "c" (c: u8) {
    if uart_base == 0 {
        return  // UART not initialized
    }

    // Wait until TX FIFO is not full
    for (mmio_read_u32(uart_base + UART_FR) & UART_FR_TXFF) != 0 {
        // Busy wait
    }

    // Write character to data register
    mmio_write_u32(uart_base + UART_DR, u32(c))
}

// Receive a single character
// Waits for RX FIFO to have data
uart_getc :: proc "c" () -> u8 {
    if uart_base == 0 {
        return 0  // UART not initialized
    }

    // Wait until RX FIFO is not empty
    for (mmio_read_u32(uart_base + UART_FR) & UART_FR_RXFE) != 0 {
        // Busy wait
    }

    // Read character from data register
    return u8(mmio_read_u32(uart_base + UART_DR) & 0xFF)
}

// Maximum string length for kernel strings
MAX_KERNEL_STRING_LENGTH :: 4096

// Transmit a null-terminated string
// SECURITY: Enforces maximum string length to prevent unbounded reads
uart_puts :: proc "c" (s: cstring) {
    if s == nil {
        return
    }

    // Iterate through string until null terminator or max length
    ptr := ([^]u8)(s)
    idx := 0
    for idx < MAX_KERNEL_STRING_LENGTH {
        c := ptr[idx]
        if c == 0 {
            return  // Proper null termination
        }
        uart_putc(c)
        idx += 1
    }

    // If we get here, string was not null-terminated within limit
    kprintln("ERROR: Non-null-terminated string detected in uart_puts")
}

// Debug print function - convenience wrapper
kprint :: proc "c" (s: cstring) {
    uart_puts(s)
}

// Debug print with newline
kprintln :: proc "c" (s: cstring) {
    uart_puts(s)
    uart_putc('\n')
}

// Print a single hexadecimal digit (0-F)
@(optimization_mode="favor_size")
print_hex_digit :: proc "c" (digit: u8) {
    if digit < 10 {
        uart_putc('0' + digit)
    } else {
        uart_putc('A' + (digit - 10))
    }
}

// Print a 64-bit value as hexadecimal
print_hex64 :: proc "c" (value: u64) {
    uart_puts("0x")

    // Print 16 hex digits (64 bits / 4 bits per digit)
    for i := 15; i >= 0; i -= 1 {
        shift := u64(i * 4)
        digit := u8((value >> shift) & 0xF)
        print_hex_digit(digit)
    }
}

// Print a 32-bit value as hexadecimal
print_hex32 :: proc "c" (value: u32) {
    uart_puts("0x")

    // Print 8 hex digits (32 bits / 4 bits per digit)
    for i := 7; i >= 0; i -= 1 {
        shift := u32(i * 4)
        digit := u8((value >> shift) & 0xF)
        print_hex_digit(digit)
    }
}

// Enable UART RX interrupts
uart_enable_rx_interrupt :: proc "c" (irq_num: u32) {
    uart_irq = irq_num

    // Register our IRQ handler
    irq_register_handler(irq_num, uart_irq_handler)

    // Enable RX interrupt in UART
    mmio_write_u32(uart_base + UART_IMSC, UART_IMSC_RXIM)

    // Enable interrupt in GIC
    gic_enable_interrupt(irq_num)

    kprint("UART RX interrupts enabled (IRQ ")
    print_hex32(irq_num)
    kprintln(")")
}

// UART IRQ handler
uart_irq_handler :: proc "c" (irq: u32) {
    // Read all available characters from UART FIFO
    for (mmio_read_u32(uart_base + UART_FR) & UART_FR_RXFE) == 0 {
        // Read character
        c := u8(mmio_read_u32(uart_base + UART_DR) & 0xFF)

        // Write to circular buffer
        uart_rx_write(c)
    }

    // Clear the RX interrupt
    mmio_write_u32(uart_base + UART_ICR, UART_IMSC_RXIM)
}

// Receive a character using interrupt-driven I/O
// Returns 0 if no character available (non-blocking)
uart_getc_nonblocking :: proc "c" () -> (u8, bool) {
    return uart_rx_read()
}

// Receive a character using interrupt-driven I/O (blocking)
uart_getc_interrupt :: proc "c" () -> u8 {
    // Wait for character in buffer
    for !uart_rx_available() {
        arm_wfe()  // Wait for event (IRQ will wake us)
    }

    c, ok := uart_rx_read()
    if !ok {
        return 0
    }
    return c
}
