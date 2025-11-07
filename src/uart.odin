package kernel

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

// Global UART base address (set by uart_init)
uart_base: uintptr = 0

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

// Transmit a null-terminated string
uart_puts :: proc "c" (s: cstring) {
    if s == nil {
        return
    }

    // Iterate through string until null terminator
    ptr := ([^]u8)(s)
    idx := 0
    for {
        c := ptr[idx]
        if c == 0 {
            break
        }
        uart_putc(c)
        idx += 1
    }
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
