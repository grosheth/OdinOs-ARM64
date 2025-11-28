package kernel

// OdinOS Interactive Shell
//
// Provides a command-line interface for user interaction with the OS.
// Features:
//  - Command input with line editing (backspace support)
//  - Command parsing and execution
//  - Built-in commands (exit, help, version, clear)
//  - Works on both QEMU and iPhone 7 via UART

// Constants
MAX_INPUT_LENGTH :: 255  // Maximum command line length (+ null terminator)
BACKSPACE :: 0x7F        // Backspace character (DEL)
BACKSPACE_ALT :: 0x08    // Alternative backspace (Ctrl+H)
NEWLINE :: '\n'          // Newline character
CARRIAGE_RETURN :: '\r'  // Carriage return

// UART register offsets and uart_base are defined in uart.odin
// We use them directly for non-blocking input handling

// Shell state
input_buffer: [256]u8    // Command line buffer (255 chars + null terminator)
buffer_pos: u32 = 0      // Current position in buffer

// Version information
OS_VERSION :: "0.4.1"
OS_TARGET :: "iPhone 7 (A10 Fusion) / ARM64"

// ============================================================================
// Phase 1: Input Buffer Management
// ============================================================================

// Clear the input buffer and reset position
buffer_clear :: proc "c" () {
    // Reset position first
    buffer_pos = 0

    // Zero out first few bytes (enough for command termination)
    // Full buffer clear not needed - we track length with buffer_pos
    input_buffer[0] = 0
}

// Add a character to the buffer
// Returns true if successful, false if buffer is full
buffer_add_char :: proc "c" (c: u8) -> bool {
    // Check for overflow - leave room for null terminator
    if buffer_pos >= MAX_INPUT_LENGTH {
        return false
    }

    // Add character to buffer
    input_buffer[buffer_pos] = c
    buffer_pos += 1

    return true
}

// Remove the last character from the buffer (backspace)
// Returns true if successful, false if buffer is empty
buffer_remove_char :: proc "c" () -> bool {
    // Check if buffer is empty
    if buffer_pos == 0 {
        return false
    }

    // Remove last character
    buffer_pos -= 1
    input_buffer[buffer_pos] = 0

    return true
}

// Get the current buffer contents as a string
// Returns pointer to buffer and length
buffer_get_contents :: proc "c" () -> (^u8, u32) {
    // Ensure null termination
    if buffer_pos < u32(len(input_buffer)) {
        input_buffer[buffer_pos] = 0
    }

    return &input_buffer[0], buffer_pos
}

// ============================================================================
// Phase 1: Character Echo and Input Handling
// ============================================================================

// Check if a character is printable (ASCII 0x20-0x7E)
is_printable :: proc "c" (c: u8) -> bool {
    return c >= 0x20 && c <= 0x7E
}

// Handle backspace - send escape sequence to erase character on screen
handle_backspace :: proc "c" () {
    if buffer_remove_char() {
        // Send backspace sequence: \b \b (back, space, back)
        uart_putc('\b')
        uart_putc(' ')
        uart_putc('\b')
    }
    // If buffer is empty, do nothing (already at start of line)
}

// ============================================================================
// Phase 2: Command Parsing
// ============================================================================

// Command structure
Command :: struct {
    name: [32]u8,      // Command name (null-terminated)
    name_len: u32,     // Length of command name
    valid: bool,       // Is this a valid parsed command?
}

// Skip leading whitespace in buffer
skip_whitespace :: proc "c" (buffer: ^u8, len: u32, start: u32) -> u32 {
    pos := start
    for pos < len {
        c := (cast(^u8)(uintptr(buffer) + uintptr(pos)))^
        if c != ' ' && c != '\t' {
            break
        }
        pos += 1
    }
    return pos
}

// Convert character to lowercase
to_lowercase :: proc "c" (c: u8) -> u8 {
    if c >= 'A' && c <= 'Z' {
        return c + ('a' - 'A')
    }
    return c
}

// Parse command from buffer
// Extracts command name, converts to lowercase, trims whitespace
parse_command :: proc "c" (buffer: ^u8, length: u32) -> Command {
    cmd: Command
    cmd.valid = false
    cmd.name_len = 0

    if length == 0 {
        return cmd  // Empty command
    }

    // Skip leading whitespace
    start := skip_whitespace(buffer, length, 0)
    if start >= length {
        return cmd  // Only whitespace
    }

    // Extract command name (until whitespace or end)
    pos := start
    cmd_idx := u32(0)
    max_name_len := u32(len(cmd.name) - 1)

    for pos < length && cmd_idx < max_name_len {
        c := (cast(^u8)(uintptr(buffer) + uintptr(pos)))^

        // Stop at whitespace
        if c == ' ' || c == '\t' {
            break
        }

        // Stop at null terminator
        if c == 0 {
            break
        }

        // Add lowercase character to command name
        cmd.name[cmd_idx] = to_lowercase(c)
        cmd_idx += 1
        pos += 1
    }

    // Null terminate
    cmd.name[cmd_idx] = 0
    cmd.name_len = cmd_idx

    // Valid if we got at least one character
    cmd.valid = cmd_idx > 0

    return cmd
}

// Compare command name with a string (case-insensitive)
command_matches :: proc "c" (cmd: ^Command, name: cstring) -> bool {
    if !cmd.valid {
        return false
    }

    // Get name length
    name_ptr := ([^]u8)(name)
    name_len := u32(0)
    for {
        if name_ptr[name_len] == 0 {
            break
        }
        name_len += 1
    }

    // Check length match
    if cmd.name_len != name_len {
        return false
    }

    // Compare characters (already lowercase in cmd.name)
    for i := u32(0); i < name_len; i += 1 {
        cmd_char := cmd.name[i]
        name_char := to_lowercase(name_ptr[i])
        if cmd_char != name_char {
            return false
        }
    }

    return true
}

// ============================================================================
// Phase 2: Command Dispatcher
// ============================================================================

// Command handler function type
Command_Handler :: proc "c" (cmd: ^Command)

// Command entry in the command table
Command_Entry :: struct {
    name: cstring,
    handler: Command_Handler,
    help: cstring,
}

// Forward declarations for command handlers
cmd_exit :: proc "c" (cmd: ^Command) {
    kprintln("\nShutting down OdinOS...")
    kprintln("Goodbye!")
    kprint("\n")

    // Flush UART output - wait for transmit to complete
    for (mmio_read_u32(uart_base + UART_FR) & UART_FR_BUSY) != 0 {
        // Wait for UART to finish transmitting
    }

    // Enter low-power halt loop
    for {
        arm_wfe()
    }
}

cmd_help :: proc "c" (cmd: ^Command) {
    kprintln("\nAvailable commands:")
    kprintln("  help    - Show this help message")
    kprintln("  version - Show OS version information")
    kprintln("  clear   - Clear the terminal screen")
    kprintln("  exit    - Shutdown the system")
    kprint("\n")
}

cmd_version :: proc "c" (cmd: ^Command) {
    kprint("\nOdinOS v")
    kprintln(OS_VERSION)
    kprint("Target: ")
    kprintln(OS_TARGET)
    kprintln("Built with Odin compiler (freestanding ARM64)")
    kprint("\n")
}

cmd_clear :: proc "c" (cmd: ^Command) {
    // VT100 escape sequence: Clear screen and move cursor to home
    kprint("\x1B[2J")   // Clear entire screen
    kprint("\x1B[H")    // Move cursor to home (1,1)
}

// Command table - list of all available commands
command_table: [4]Command_Entry = {
    {"help",    cmd_help,    "Show available commands"},
    {"version", cmd_version, "Show OS version"},
    {"clear",   cmd_clear,   "Clear the screen"},
    {"exit",    cmd_exit,    "Shutdown the system"},
}

// Execute a command by dispatching to the appropriate handler
execute_command :: proc "c" (cmd: ^Command) {
    if !cmd.valid {
        return  // Empty command, do nothing
    }

    // Search command table
    for i := 0; i < len(command_table); i += 1 {
        entry := &command_table[i]
        if command_matches(cmd, entry.name) {
            // Found matching command, execute it
            entry.handler(cmd)
            return
        }
    }

    // Unknown command
    kprint("Unknown command: ")
    // Print command name
    for i := u32(0); i < cmd.name_len; i += 1 {
        uart_putc(cmd.name[i])
    }
    kprintln("")
    kprintln("Type 'help' for available commands.")
}

// ============================================================================
// Phase 3: Shell Main Loop
// ============================================================================

// Display the shell prompt
show_prompt :: proc "c" () {
    kprint("OdinOS> ")
}

// Process a single character of input
handle_character :: proc "c" (c: u8) {
    // Handle backspace
    if c == BACKSPACE || c == BACKSPACE_ALT {
        handle_backspace()
        return
    }

    // Handle newline/carriage return - execute command
    if c == NEWLINE || c == CARRIAGE_RETURN {
        kprint("\n")  // Echo newline

        // Parse and execute command
        buf, length := buffer_get_contents()
        cmd := parse_command(buf, length)
        execute_command(&cmd)

        // Clear buffer and show new prompt
        buffer_clear()
        show_prompt()
        return
    }

    // Handle printable characters
    if is_printable(c) {
        // Try to add to buffer
        if buffer_add_char(c) {
            // Echo character back to terminal
            uart_putc(c)
        } else {
            // Buffer full - beep or ignore
            uart_putc(0x07)  // BEL character (beep)
        }
        return
    }

    // Ignore other control characters
}

// Initialize the shell
shell_init :: proc "c" () {
    buffer_clear()

    kprintln("\n========================================")
    kprintln("   OdinOS Interactive Shell v0.4.1")
    kprintln("========================================")
    kprint("\n")
}

// Main shell loop - read characters and process commands
shell_run :: proc "c" () {
    kprintln("Interactive shell starting...")
    kprintln("Type 'help' for available commands")
    kprint("\n")

    // Main input loop
    for {
        // Show prompt
        kprint("OdinOS> ")

        // Clear buffer for new command
        buffer_clear()

        // Read command line
        command_complete := false
        for !command_complete {
            // Wait for and read character using interrupt-driven I/O
            c := uart_getc_interrupt()

            // Handle newline/carriage return
            if c == NEWLINE || c == CARRIAGE_RETURN {
                uart_putc('\n')  // Echo newline
                command_complete = true
                continue
            }

            // Handle backspace
            if c == BACKSPACE || c == BACKSPACE_ALT {
                handle_backspace()
                continue
            }

            // Handle printable characters
            if is_printable(c) {
                if buffer_add_char(c) {
                    uart_putc(c)  // Echo character
                } else {
                    uart_putc(0x07)  // Buffer full - beep
                }
                continue
            }

            // Ignore other control characters
        }

        // Get command from buffer
        cmd_ptr, cmd_len := buffer_get_contents()
        if cmd_len > 0 {
            // Parse and execute command
            cmd := parse_command(cmd_ptr, cmd_len)
            execute_command(&cmd)
        }
    }
}

// Note: mask_interrupts removed - we now have proper interrupt handling!
