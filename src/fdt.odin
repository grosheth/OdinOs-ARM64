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
cstring_equal :: proc "c" (s1: cstring, s2: cstring) -> bool {
    if s1 == nil || s2 == nil {
        return false
    }

    p1 := ([^]u8)(s1)
    p2 := ([^]u8)(s2)
    idx := 0

    for {
        c1 := p1[idx]
        c2 := p2[idx]

        if c1 != c2 {
            return false
        }

        if c1 == 0 {
            return true  // Both strings ended at same point
        }

        idx += 1
    }

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

// Search for UART device in device tree
// Returns UART base address, or 0 if not found
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
cstring_contains :: proc "c" (haystack: cstring, needle: cstring) -> bool {
    if haystack == nil || needle == nil {
        return false
    }

    h := ([^]u8)(haystack)
    n := ([^]u8)(needle)

    // Get needle length
    needle_len := 0
    for {
        if n[needle_len] == 0 {
            break
        }
        needle_len += 1
    }

    if needle_len == 0 {
        return false
    }

    // Search for needle in haystack
    h_idx := 0
    for {
        if h[h_idx] == 0 {
            break
        }

        // Try to match needle starting at current position
        match := true
        for n_idx := 0; n_idx < needle_len; n_idx += 1 {
            if h[h_idx + n_idx] != n[n_idx] {
                match = false
                break
            }
        }

        if match {
            return true
        }

        h_idx += 1
    }

    return false
}
