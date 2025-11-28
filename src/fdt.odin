package kernel

// Flattened Device Tree (FDT) Parser
//
// Parses the device tree blob passed by the bootloader (iBoot on iPhone 7, QEMU on virt machine)
// to discover hardware addresses dynamically instead of hardcoding them.
//
// Device tree format is big-endian, so all multi-byte values must be byte-swapped.
//
// References:
//  - Device Tree Specification v0.3
//  - Linux kernel's libfdt implementation
//  - iBoot passes device tree address in x0 on iPhone 7

// FDT Magic number (big-endian)
FDT_MAGIC :: 0xd00dfeed

// FDT Token types
FDT_BEGIN_NODE :: 0x00000001
FDT_END_NODE   :: 0x00000002
FDT_PROP       :: 0x00000003
FDT_NOP        :: 0x00000004
FDT_END        :: 0x00000009

// FDT Header (all fields are big-endian)
FDT_Header :: struct #packed {
    magic:              u32,  // 0xd00dfeed
    totalsize:          u32,  // Total size of device tree blob
    off_dt_struct:      u32,  // Offset to structure block
    off_dt_strings:     u32,  // Offset to strings block
    off_mem_rsvmap:     u32,  // Offset to memory reservation block
    version:            u32,  // Device tree version
    last_comp_version:  u32,  // Last compatible version
    boot_cpuid_phys:    u32,  // Physical CPU ID of boot CPU
    size_dt_strings:    u32,  // Size of strings block
    size_dt_struct:     u32,  // Size of structure block
}

// Global device tree pointer (set during boot)
fdt_base: uintptr = 0
fdt_totalsize: u32 = 0  // Total size of device tree (for bounds checking)

// Security constants
MAX_DT_SIZE :: 16 * 1024 * 1024  // 16MB max device tree size
MAX_PROPERTY_SIZE :: 1024 * 1024  // 1MB max property size
MAX_STRING_LENGTH :: 4096         // Max string length in device tree

// Byte-swap utilities for big-endian device tree data
bswap32 :: proc "c" (val: u32) -> u32 {
    return ((val << 24) & 0xFF000000) |
           ((val <<  8) & 0x00FF0000) |
           ((val >>  8) & 0x0000FF00) |
           ((val >> 24) & 0x000000FF)
}

bswap64 :: proc "c" (val: u64) -> u64 {
    return ((val << 56) & 0xFF00000000000000) |
           ((val << 40) & 0x00FF000000000000) |
           ((val << 24) & 0x0000FF0000000000) |
           ((val <<  8) & 0x000000FF00000000) |
           ((val >>  8) & 0x00000000FF000000) |
           ((val >> 24) & 0x0000000000FF0000) |
           ((val >> 40) & 0x000000000000FF00) |
           ((val >> 56) & 0x00000000000000FF)
}

// Read big-endian u32 from device tree
fdt_read_u32 :: proc "c" (addr: uintptr) -> u32 {
    value := (^u32)(addr)^
    return bswap32(value)
}

// Read big-endian u64 from device tree
fdt_read_u64 :: proc "c" (addr: uintptr) -> u64 {
    value := (^u64)(addr)^
    return bswap64(value)
}

// ============================================================================
// SECURITY: Bounds-checked device tree access functions
// ============================================================================

// Safely read u32 from device tree with bounds checking
fdt_read_u32_safe :: proc "c" (base: uintptr, struct_offset: u32, offset: u32, struct_size: u32) -> (u32, bool) {
    // Check offset is within bounds (with room for u32)
    if offset > struct_size || offset > struct_size - 4 {
        kprintln("ERROR: Device tree read out of bounds")
        return 0, false
    }

    value := fdt_read_u32(base + uintptr(struct_offset) + uintptr(offset))
    return value, true
}

// Safely advance offset with overflow and bounds checking
fdt_advance_offset_safe :: proc "c" (offset: u32, advancement: u32, struct_size: u32) -> (u32, bool) {
    // Check for overflow
    new_offset := offset + advancement

    // Detect wraparound
    if new_offset < offset {
        kprintln("ERROR: Device tree offset overflow detected")
        return 0, false
    }

    // Check bounds
    if new_offset > struct_size {
        kprintln("ERROR: Device tree offset exceeds structure size")
        return 0, false
    }

    return new_offset, true
}

// Safely align offset with overflow and bounds checking
fdt_align_offset_safe :: proc "c" (offset: u32, alignment: u32, struct_size: u32) -> (u32, bool) {
    aligned := (offset + (alignment - 1)) & ~(alignment - 1)

    // Check for overflow during alignment
    if aligned < offset {
        kprintln("ERROR: Offset overflow during alignment")
        return 0, false
    }

    if aligned > struct_size {
        kprintln("ERROR: Aligned offset exceeds structure size")
        return 0, false
    }

    return aligned, true
}

// Safely read null-terminated string from device tree
// Advances offset and returns true if successful
fdt_read_string_safe :: proc "c" (base: uintptr, struct_offset: u32, offset: ^u32, struct_size: u32, max_len: u32) -> bool {
    start_offset := offset^

    for {
        if offset^ >= struct_size {
            kprintln("ERROR: Device tree string exceeds bounds")
            offset^ = start_offset  // Restore
            return false
        }

        if (offset^ - start_offset) > max_len {
            kprintln("ERROR: Device tree string too long")
            offset^ = start_offset
            return false
        }

        c := (^u8)(base + uintptr(struct_offset) + uintptr(offset^))^
        offset^ += 1

        if c == 0 {
            break
        }
    }

    return true
}

// Initialize device tree parser
// dt_addr: Address of device tree blob (passed by bootloader in x0)
// Returns: true if valid device tree, false otherwise
fdt_init :: proc "c" (dt_addr: uintptr) -> bool {
    if dt_addr == 0 {
        kprintln("ERROR: Device tree address is NULL")
        return false
    }

    fdt_base = dt_addr

    // Read and validate header
    header := (^FDT_Header)(fdt_base)
    magic := bswap32(header.magic)

    if magic != FDT_MAGIC {
        kprint("ERROR: Invalid device tree magic: ")
        print_hex32(magic)
        kprint(" (expected ")
        print_hex32(FDT_MAGIC)
        kprintln(")")
        return false
    }

    version := bswap32(header.version)
    totalsize := bswap32(header.totalsize)

    // SECURITY: Validate device tree size is reasonable
    if totalsize > MAX_DT_SIZE {
        kprint("ERROR: Device tree too large: ")
        print_hex32(totalsize)
        kprint(" (max ")
        print_hex32(MAX_DT_SIZE)
        kprintln(")")
        return false
    }

    if totalsize < size_of(FDT_Header) {
        kprint("ERROR: Device tree too small: ")
        print_hex32(totalsize)
        kprintln("")
        return false
    }

    // Store totalsize globally for bounds checking
    fdt_totalsize = totalsize

    kprint("Device tree found at ")
    print_hex64(u64(dt_addr))
    kprintln("")
    kprint("  Version: ")
    print_hex32(version)
    kprintln("")
    kprint("  Total size: ")
    print_hex32(totalsize)
    kprintln(" bytes")

    return true
}

// Find a property in the current node
// Returns pointer to property value and size, or (0, 0) if not found
fdt_get_property :: proc "c" (node_offset: u32, property_name: cstring) -> (uintptr, u32) {
    if fdt_base == 0 {
        return 0, 0
    }

    header := (^FDT_Header)(fdt_base)
    struct_offset := bswap32(header.off_dt_struct)
    strings_offset := bswap32(header.off_dt_strings)

    // Start at the given node offset
    offset := struct_offset + node_offset

    // Skip the FDT_BEGIN_NODE token and node name
    token := fdt_read_u32(fdt_base + uintptr(offset))
    if token != FDT_BEGIN_NODE {
        return 0, 0
    }
    offset += 4

    // Skip node name (null-terminated, aligned to 4 bytes)
    for {
        c := (^u8)(fdt_base + uintptr(offset))^
        offset += 1
        if c == 0 {
            break
        }
    }
    // Align to 4 bytes
    offset = (offset + 3) & ~u32(3)

    // Search for properties
    for {
        token = fdt_read_u32(fdt_base + uintptr(offset))
        offset += 4

        if token == FDT_PROP {
            // Read property header
            prop_len := fdt_read_u32(fdt_base + uintptr(offset))
            offset += 4
            name_offset := fdt_read_u32(fdt_base + uintptr(offset))
            offset += 4

            // Get property name from strings block
            name_addr := fdt_base + uintptr(strings_offset) + uintptr(name_offset)

            // Compare with requested property name
            if cstring_equal(cstring((^u8)(name_addr)), property_name) {
                // Found it! Return pointer to value and length
                value_addr := fdt_base + uintptr(offset)
                return value_addr, prop_len
            }

            // Skip property value (aligned to 4 bytes)
            offset += (prop_len + 3) & ~u32(3)

        } else if token == FDT_BEGIN_NODE {
            // Nested node, skip it
            return 0, 0
        } else if token == FDT_END_NODE || token == FDT_END {
            // End of node or device tree
            return 0, 0
        } else if token == FDT_NOP {
            // Skip NOP tokens
            continue
        } else {
            // Unknown token
            return 0, 0
        }
    }

    return 0, 0
}

// Compare two null-terminated strings
// Returns true if equal
// SECURITY: Enforces maximum string length to prevent unbounded reads
cstring_equal :: proc "c" (s1: cstring, s2: cstring) -> bool {
    if s1 == nil || s2 == nil {
        return false
    }

    p1 := ([^]u8)(s1)
    p2 := ([^]u8)(s2)

    for idx := 0; idx < MAX_STRING_LENGTH; idx += 1 {
        c1 := p1[idx]
        c2 := p2[idx]

        if c1 != c2 {
            return false
        }

        if c1 == 0 {
            return true  // Both strings ended at same point
        }
    }

    // Strings equal up to max length but not null-terminated
    kprintln("WARNING: String comparison exceeded maximum length")
    return false
}

// Find a node by path (e.g., "/soc/uart@9000000")
// Returns offset from struct block, or 0xFFFFFFFF if not found
fdt_find_node :: proc "c" (path: cstring) -> u32 {
    if fdt_base == 0 {
        return 0xFFFFFFFF
    }

    header := (^FDT_Header)(fdt_base)
    struct_offset := bswap32(header.off_dt_struct)

    // For now, just return 0 to search from root
    // TODO: Implement full path traversal
    return 0
}

// UART information structure
UART_Info :: struct {
    base_address: uintptr,
    irq_number: u32,
    found: bool,
}

// Search for UART device in device tree
// Returns UART base address and IRQ number
fdt_find_uart_full :: proc "c" () -> UART_Info {
    result := UART_Info{0, 0, false}

    if fdt_base == 0 {
        kprintln("ERROR: Device tree not initialized")
        return result
    }

    kprintln("Searching device tree for UART...")

    header := (^FDT_Header)(fdt_base)
    struct_offset := bswap32(header.off_dt_struct)
    struct_size := bswap32(header.size_dt_struct)
    strings_offset := bswap32(header.off_dt_strings)

    // SECURITY: Validate struct_size is within device tree bounds
    if struct_size > fdt_totalsize {
        kprintln("ERROR: Device tree struct_size exceeds totalsize")
        return result
    }

    offset := u32(0)
    depth := 0
    current_node_is_uart := false

    // SECURITY: Limit iteration count to prevent infinite loops
    MAX_ITERATIONS :: 10000
    iteration_count := u32(0)

    // Traverse the entire device tree structure
    for offset < struct_size {
        // SECURITY: Check iteration limit
        iteration_count += 1
        if iteration_count > MAX_ITERATIONS {
            kprintln("ERROR: Device tree parsing exceeded iteration limit")
            return result
        }

        // SECURITY: Bounds-checked token read
        token, ok := fdt_read_u32_safe(fdt_base, struct_offset, offset, struct_size)
        if !ok {
            return result
        }

        new_offset, ok2 := fdt_advance_offset_safe(offset, 4, struct_size)
        if !ok2 {
            return result
        }
        offset = new_offset

        if token == FDT_BEGIN_NODE {
            depth += 1

            // Read node name (for checking if it's UART)
            node_name := cstring((^u8)(fdt_base + uintptr(struct_offset) + uintptr(offset)))

            // SECURITY: Skip node name safely with bounds checking
            if !fdt_read_string_safe(fdt_base, struct_offset, &offset, struct_size, MAX_STRING_LENGTH) {
                return result
            }

            // SECURITY: Align to 4 bytes safely
            aligned_offset, ok3 := fdt_align_offset_safe(offset, 4, struct_size)
            if !ok3 {
                return result
            }
            offset = aligned_offset

            // Check if this node is a UART
            current_node_is_uart = cstring_contains(node_name, "uart") ||
                                   cstring_contains(node_name, "serial") ||
                                   cstring_contains(node_name, "pl011")

            if current_node_is_uart {
                kprint("  Found potential UART node: ")
                kprintln(node_name)
            }

        } else if token == FDT_END_NODE {
            depth -= 1
            if current_node_is_uart && result.base_address != 0 {
                // We found both address and IRQ
                return result
            }
            current_node_is_uart = false

        } else if token == FDT_PROP {
            // SECURITY: Bounds-checked property length read
            prop_len, ok4 := fdt_read_u32_safe(fdt_base, struct_offset, offset, struct_size)
            if !ok4 {
                return result
            }

            new_offset, ok5 := fdt_advance_offset_safe(offset, 4, struct_size)
            if !ok5 {
                return result
            }
            offset = new_offset

            // SECURITY: Bounds-checked name offset read
            name_offset, ok6 := fdt_read_u32_safe(fdt_base, struct_offset, offset, struct_size)
            if !ok6 {
                return result
            }

            offset_temp, ok7 := fdt_advance_offset_safe(offset, 4, struct_size)
            if !ok7 {
                return result
            }
            offset = offset_temp

            // SECURITY: Validate property length is reasonable
            if prop_len > MAX_PROPERTY_SIZE {
                kprintln("ERROR: Device tree property too large")
                return result
            }

            // Get property name
            prop_name := cstring((^u8)(fdt_base + uintptr(strings_offset) + uintptr(name_offset)))

            // If in UART node and found "reg", extract address
            if current_node_is_uart && cstring_equal(prop_name, "reg") {
                if prop_len >= 4 {
                    addr_hi, ok8 := fdt_read_u32_safe(fdt_base, struct_offset, offset, struct_size)
                    if !ok8 {
                        return result
                    }

                    if prop_len >= 8 {
                        addr_lo, ok9 := fdt_read_u32_safe(fdt_base, struct_offset, offset + 4, struct_size)
                        if !ok9 {
                            return result
                        }
                        result.base_address = uintptr((u64(addr_hi) << 32) | u64(addr_lo))
                    } else {
                        result.base_address = uintptr(addr_hi)
                    }

                    kprint("    UART address: ")
                    print_hex64(u64(result.base_address))
                    kprintln("")
                    result.found = true
                }
            }

            // If in UART node and found "interrupts", extract IRQ number
            if current_node_is_uart && cstring_equal(prop_name, "interrupts") {
                if prop_len >= 12 {
                    // Format is usually: <type irq flags>
                    // Skip first value (type), read second value (IRQ number)
                    irq_num, ok10 := fdt_read_u32_safe(fdt_base, struct_offset, offset + 4, struct_size)
                    if !ok10 {
                        return result
                    }
                    result.irq_number = irq_num

                    kprint("    UART IRQ: ")
                    print_hex32(irq_num)
                    kprintln("")
                }
            }

            // SECURITY: Skip property value safely with alignment
            advancement := (prop_len + 3) & ~u32(3)
            offset_temp2, ok11 := fdt_advance_offset_safe(offset, advancement, struct_size)
            if !ok11 {
                return result
            }
            offset = offset_temp2

        } else if token == FDT_NOP {
            continue

        } else if token == FDT_END {
            break
        }
    }

    if !result.found {
        kprintln("WARNING: No UART found in device tree")
    }
    return result
}

// Legacy function for compatibility
fdt_find_uart :: proc "c" () -> uintptr {
    if fdt_base == 0 {
        kprintln("ERROR: Device tree not initialized")
        return 0
    }

    kprintln("Searching device tree for UART...")

    header := (^FDT_Header)(fdt_base)
    struct_offset := bswap32(header.off_dt_struct)
    struct_size := bswap32(header.size_dt_struct)
    strings_offset := bswap32(header.off_dt_strings)

    offset := u32(0)
    depth := 0
    current_node_is_uart := false

    // Traverse the entire device tree structure
    for offset < struct_size {
        token := fdt_read_u32(fdt_base + uintptr(struct_offset) + uintptr(offset))
        offset += 4

        if token == FDT_BEGIN_NODE {
            depth += 1

            // Read node name
            name_start := offset
            node_name := cstring((^u8)(fdt_base + uintptr(struct_offset) + uintptr(offset)))

            // Skip node name (null-terminated)
            for {
                c := (^u8)(fdt_base + uintptr(struct_offset) + uintptr(offset))^
                offset += 1
                if c == 0 {
                    break
                }
            }
            // Align to 4 bytes
            offset = (offset + 3) & ~u32(3)

            // Check if this node is a UART
            // Look for "uart", "serial", or "pl011" in the node name
            // Examples: "uart@9000000", "serial@...", "pl011@9000000"
            current_node_is_uart = cstring_contains(node_name, "uart") ||
                                   cstring_contains(node_name, "serial") ||
                                   cstring_contains(node_name, "pl011")

            if current_node_is_uart {
                kprint("  Found potential UART node: ")
                kprintln(node_name)
            }

        } else if token == FDT_END_NODE {
            depth -= 1
            current_node_is_uart = false

        } else if token == FDT_PROP {
            prop_len := fdt_read_u32(fdt_base + uintptr(struct_offset) + uintptr(offset))
            offset += 4
            name_offset := fdt_read_u32(fdt_base + uintptr(struct_offset) + uintptr(offset))
            offset += 4

            // Get property name
            prop_name := cstring((^u8)(fdt_base + uintptr(strings_offset) + uintptr(name_offset)))

            // If we're in a UART node and found the "reg" property, extract the address
            if current_node_is_uart && cstring_equal(prop_name, "reg") {
                kprint("    Found 'reg' property, length: ")
                print_hex32(prop_len)
                kprintln("")

                // Read the first address from the reg property
                // Format is usually: <address size> or <address_hi address_lo size_hi size_lo>
                if prop_len >= 4 {
                    // Read first 32-bit value (or high part of 64-bit address)
                    addr_hi := fdt_read_u32(fdt_base + uintptr(struct_offset) + uintptr(offset))

                    if prop_len >= 8 {
                        // 64-bit address
                        addr_lo := fdt_read_u32(fdt_base + uintptr(struct_offset) + uintptr(offset + 4))
                        uart_addr := (u64(addr_hi) << 32) | u64(addr_lo)

                        kprint("    UART address (64-bit): ")
                        print_hex64(uart_addr)
                        kprintln("")

                        return uintptr(uart_addr)
                    } else {
                        // 32-bit address
                        uart_addr := u64(addr_hi)

                        kprint("    UART address (32-bit): ")
                        print_hex64(uart_addr)
                        kprintln("")

                        return uintptr(uart_addr)
                    }
                }
            }

            // Skip property value (aligned to 4 bytes)
            offset += (prop_len + 3) & ~u32(3)

        } else if token == FDT_NOP {
            // Skip NOP tokens
            continue

        } else if token == FDT_END {
            // End of device tree
            break
        }
    }

    kprintln("WARNING: No UART found in device tree")
    return 0
}

// Check if a string contains a substring
// SECURITY: Enforces maximum string length to prevent unbounded reads
cstring_contains :: proc "c" (haystack: cstring, needle: cstring) -> bool {
    if haystack == nil || needle == nil {
        return false
    }

    h := ([^]u8)(haystack)
    n := ([^]u8)(needle)

    // Get needle length (bounded)
    needle_len := 0
    for needle_len < MAX_STRING_LENGTH {
        if n[needle_len] == 0 {
            break
        }
        needle_len += 1
    }

    if needle_len == 0 || needle_len >= MAX_STRING_LENGTH {
        return false
    }

    // Search for needle in haystack (bounded)
    for h_idx := 0; h_idx < MAX_STRING_LENGTH; h_idx += 1 {
        if h[h_idx] == 0 {
            break
        }

        // Try to match needle starting at current position
        match := true
        for n_idx := 0; n_idx < needle_len; n_idx += 1 {
            if (h_idx + n_idx) >= MAX_STRING_LENGTH {
                return false  // Would exceed bounds
            }
            if h[h_idx + n_idx] != n[n_idx] {
                match = false
                break
            }
        }

        if match {
            return true
        }
    }

    return false
}

// GIC addresses structure
GIC_Addresses :: struct {
    distributor_base: uintptr,  // GICD base address
    cpu_interface_base: uintptr, // GICC base address
    found: bool,
}

// Search for GIC (Generic Interrupt Controller) in device tree
// Returns GIC distributor and CPU interface base addresses
fdt_find_gic :: proc "c" () -> GIC_Addresses {
    result := GIC_Addresses{0, 0, false}

    if fdt_base == 0 {
        kprintln("ERROR: Device tree not initialized")
        return result
    }

    kprintln("Searching device tree for GIC...")

    header := (^FDT_Header)(fdt_base)
    struct_offset := bswap32(header.off_dt_struct)
    struct_size := bswap32(header.size_dt_struct)
    strings_offset := bswap32(header.off_dt_strings)

    // SECURITY: Validate struct_size is within device tree bounds
    if struct_size > fdt_totalsize {
        kprintln("ERROR: Device tree struct_size exceeds totalsize")
        return result
    }

    offset := u32(0)
    depth := 0
    current_node_is_gic := false

    // SECURITY: Limit iteration count to prevent infinite loops
    MAX_ITERATIONS :: 10000
    iteration_count := u32(0)

    // Traverse the entire device tree structure
    for offset < struct_size {
        // SECURITY: Check iteration limit
        iteration_count += 1
        if iteration_count > MAX_ITERATIONS {
            kprintln("ERROR: Device tree parsing exceeded iteration limit (GIC)")
            return result
        }

        // SECURITY: Bounds-checked token read
        token, ok := fdt_read_u32_safe(fdt_base, struct_offset, offset, struct_size)
        if !ok {
            return result
        }

        new_offset, ok2 := fdt_advance_offset_safe(offset, 4, struct_size)
        if !ok2 {
            return result
        }
        offset = new_offset

        if token == FDT_BEGIN_NODE {
            depth += 1

            // Read node name (for checking if it's GIC)
            node_name := cstring((^u8)(fdt_base + uintptr(struct_offset) + uintptr(offset)))

            // SECURITY: Skip node name safely with bounds checking
            if !fdt_read_string_safe(fdt_base, struct_offset, &offset, struct_size, MAX_STRING_LENGTH) {
                return result
            }

            // SECURITY: Align to 4 bytes safely
            aligned_offset, ok3 := fdt_align_offset_safe(offset, 4, struct_size)
            if !ok3 {
                return result
            }
            offset = aligned_offset

            // Check if this node is a GIC
            // Look for "interrupt-controller@", "gic@", or "intc@" in the node name
            // Examples: "interrupt-controller@8000000", "gic@8000000"
            current_node_is_gic = cstring_contains(node_name, "interrupt-controller") ||
                                  cstring_contains(node_name, "gic@") ||
                                  cstring_contains(node_name, "intc@")

            if current_node_is_gic {
                kprint("  Found potential GIC node: ")
                kprintln(node_name)
            }

        } else if token == FDT_END_NODE {
            depth -= 1
            current_node_is_gic = false

        } else if token == FDT_PROP {
            // SECURITY: Bounds-checked property length read
            prop_len, ok4 := fdt_read_u32_safe(fdt_base, struct_offset, offset, struct_size)
            if !ok4 {
                return result
            }

            new_offset, ok5 := fdt_advance_offset_safe(offset, 4, struct_size)
            if !ok5 {
                return result
            }
            offset = new_offset

            // SECURITY: Bounds-checked name offset read
            name_offset, ok6 := fdt_read_u32_safe(fdt_base, struct_offset, offset, struct_size)
            if !ok6 {
                return result
            }

            offset_temp, ok7 := fdt_advance_offset_safe(offset, 4, struct_size)
            if !ok7 {
                return result
            }
            offset = offset_temp

            // SECURITY: Validate property length is reasonable
            if prop_len > MAX_PROPERTY_SIZE {
                kprintln("ERROR: Device tree property too large (GIC)")
                return result
            }

            // Get property name
            prop_name := cstring((^u8)(fdt_base + uintptr(strings_offset) + uintptr(name_offset)))

            // Check if this is a GIC by looking for "compatible" property
            if current_node_is_gic && cstring_equal(prop_name, "compatible") {
                compat_str := cstring((^u8)(fdt_base + uintptr(struct_offset) + uintptr(offset)))

                // Check for known GIC compatible strings
                is_gic := cstring_contains(compat_str, "arm,gic-400") ||
                         cstring_contains(compat_str, "arm,cortex-a15-gic") ||
                         cstring_contains(compat_str, "arm,cortex-a9-gic") ||
                         cstring_contains(compat_str, "arm,gic-v2")

                if is_gic {
                    kprint("    Confirmed GIC device: ")
                    kprintln(compat_str)
                }
            }

            // If we're in a GIC node and found the "reg" property, extract addresses
            if current_node_is_gic && cstring_equal(prop_name, "reg") {
                kprint("    Found 'reg' property, length: ")
                print_hex32(prop_len)
                kprintln("")

                // GIC reg format can vary:
                // QEMU virt with #address-cells=2, #size-cells=2:
                //   reg = <0x0 0x08000000 0x0 0x10000 0x0 0x08010000 0x0 0x10000>;
                //   That's 8 x u32 values (4 pairs of u64): GICD_base_hi GICD_base_lo GICD_size_hi GICD_size_lo GICC_base_hi GICC_base_lo GICC_size_hi GICC_size_lo
                //
                // Or with #address-cells=1, #size-cells=1:
                //   reg = <0x08000000 0x10000 0x08010000 0x10000>;
                //   That's 4 x u32 values: GICD_base GICD_size GICC_base GICC_size

                if prop_len >= 32 {
                    // 64-bit addresses (8 u32 values)
                    // SECURITY: Bounds-checked reads for GIC addresses
                    distributor_base_hi, ok8 := fdt_read_u32_safe(fdt_base, struct_offset, offset, struct_size)
                    if !ok8 {
                        return result
                    }

                    distributor_base_lo, ok9 := fdt_read_u32_safe(fdt_base, struct_offset, offset + 4, struct_size)
                    if !ok9 {
                        return result
                    }

                    distributor_base := (u64(distributor_base_hi) << 32) | u64(distributor_base_lo)

                    // Skip GICD size (2 u32 values)
                    // Read GICC base (hi:lo)
                    cpu_interface_base_hi, ok10 := fdt_read_u32_safe(fdt_base, struct_offset, offset + 16, struct_size)
                    if !ok10 {
                        return result
                    }

                    cpu_interface_base_lo, ok11 := fdt_read_u32_safe(fdt_base, struct_offset, offset + 20, struct_size)
                    if !ok11 {
                        return result
                    }

                    cpu_interface_base := (u64(cpu_interface_base_hi) << 32) | u64(cpu_interface_base_lo)

                    result.distributor_base = uintptr(distributor_base)
                    result.cpu_interface_base = uintptr(cpu_interface_base)
                    result.found = true

                    kprint("    GIC Distributor base: ")
                    print_hex64(distributor_base)
                    kprintln("")
                    kprint("    GIC CPU Interface base: ")
                    print_hex64(cpu_interface_base)
                    kprintln("")

                    return result
                } else if prop_len >= 16 {
                    // 32-bit addresses (4 u32 values)
                    // SECURITY: Bounds-checked reads
                    distributor_base, ok12 := fdt_read_u32_safe(fdt_base, struct_offset, offset, struct_size)
                    if !ok12 {
                        return result
                    }

                    // Skip distributor size
                    cpu_interface_base, ok13 := fdt_read_u32_safe(fdt_base, struct_offset, offset + 8, struct_size)
                    if !ok13 {
                        return result
                    }

                    result.distributor_base = uintptr(distributor_base)
                    result.cpu_interface_base = uintptr(cpu_interface_base)
                    result.found = true

                    kprint("    GIC Distributor base: ")
                    print_hex64(u64(result.distributor_base))
                    kprintln("")
                    kprint("    GIC CPU Interface base: ")
                    print_hex64(u64(result.cpu_interface_base))
                    kprintln("")

                    return result
                }
            }

            // SECURITY: Skip property value safely with alignment
            advancement := (prop_len + 3) & ~u32(3)
            offset_temp3, ok14 := fdt_advance_offset_safe(offset, advancement, struct_size)
            if !ok14 {
                return result
            }
            offset = offset_temp3

        } else if token == FDT_NOP {
            // Skip NOP tokens
            continue

        } else if token == FDT_END {
            // End of device tree
            break
        }
    }

    kprintln("WARNING: No GIC found in device tree")
    return result
}
