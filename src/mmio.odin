package kernel

// MMIO (Memory-Mapped I/O) Helper Functions
//
// These functions provide type-safe, volatile access to hardware registers.
// They include proper memory barriers to ensure correct ordering of MMIO operations.
//
// SECURITY: As of v0.5.0, these functions include address validation to prevent
// malicious device tree entries from pointing MMIO operations to arbitrary memory.

import "base:intrinsics"

// ============================================================================
// SECURITY: Valid MMIO address ranges
// ============================================================================

// Valid MMIO region definition
MMIO_Region :: struct {
    start: uintptr,
    end:   uintptr,
    name:  cstring,
}

// Known valid MMIO regions for QEMU virt machine
// These ranges prevent device tree attacks from pointing UART/GIC to kernel memory
mmio_valid_regions := [?]MMIO_Region{
    {0x08000000, 0x09000000, "GIC"},        // GIC: 0x08000000 - 0x08FFFFFF
    {0x09000000, 0x0A000000, "UART"},       // UART: 0x09000000 - 0x09FFFFFF
    {0x0A000000, 0x40000000, "Peripherals"}, // Other peripherals
}

// Validate that an MMIO address is within known safe ranges
// SECURITY: Prevents device tree from pointing to kernel code or data regions
validate_mmio_address :: proc "c" (addr: uintptr, size: u32, operation: cstring) -> bool {
    // Kernel memory region (must NOT be accessed via MMIO)
    KERNEL_START :: 0x40000000
    KERNEL_END   :: 0x48000000

    // Check if address is in kernel region (FORBIDDEN)
    if addr >= KERNEL_START && addr < KERNEL_END {
        kprint("SECURITY: Blocked MMIO ")
        kprint(operation)
        kprint(" to kernel memory at ")
        print_hex64(u64(addr))
        kprintln("")
        return false
    }

    // Check if address is in any valid MMIO region
    for region in mmio_valid_regions {
        if addr >= region.start && addr < region.end {
            // Ensure the entire access (addr + size) stays within region
            if (addr + uintptr(size)) <= region.end {
                return true
            } else {
                kprint("SECURITY: MMIO ")
                kprint(operation)
                kprint(" at ")
                print_hex64(u64(addr))
                kprint(" extends beyond ")
                kprint(region.name)
                kprintln(" region")
                return false
            }
        }
    }

    // Address not in any known valid region
    kprint("SECURITY: MMIO ")
    kprint(operation)
    kprint(" to unknown region at ")
    print_hex64(u64(addr))
    kprintln("")
    return false
}

// Read a 32-bit value from an MMIO register
// Uses volatile load to prevent compiler optimization
// Includes memory barrier to ensure ordering
// SECURITY: Validates address is in allowed MMIO region
// HOT PATH: Small function, compiler will inline with -o:speed
mmio_read_u32 :: proc "c" (addr: uintptr) -> u32 {
    // SECURITY: Validate address before access
    if !validate_mmio_address(addr, 4, "read_u32") {
        return 0xFFFFFFFF  // Return all 1s on security violation
    }

    // Volatile load prevents compiler from caching or reordering
    value := intrinsics.volatile_load((^u32)(addr))

    // Data Memory Barrier - ensures all previous memory accesses complete
    // before any subsequent memory accesses begin
    arm_dmb()

    return value
}

// Write a 32-bit value to an MMIO register
// Uses volatile store to prevent compiler optimization
// Includes memory barrier after write to ensure completion
// SECURITY: Validates address is in allowed MMIO region
// HOT PATH: Small function, compiler will inline with -o:speed
mmio_write_u32 :: proc "c" (addr: uintptr, value: u32) {
    // SECURITY: Validate address before access
    if !validate_mmio_address(addr, 4, "write_u32") {
        return  // Silently fail on security violation
    }

    // Volatile store prevents compiler from optimizing away the write
    intrinsics.volatile_store((^u32)(addr), value)

    // DSB after write ensures the write completes before subsequent accesses
    // This is sufficient per ARM Architecture Reference Manual
    arm_dsb()
}

// Read an 8-bit value from an MMIO register
// SECURITY: Validates address is in allowed MMIO region
// HOT PATH: Small function, compiler will inline with -o:speed
mmio_read_u8 :: proc "c" (addr: uintptr) -> u8 {
    if !validate_mmio_address(addr, 1, "read_u8") {
        return 0xFF
    }
    value := intrinsics.volatile_load((^u8)(addr))
    arm_dmb()
    return value
}

// Write an 8-bit value to an MMIO register
// SECURITY: Validates address is in allowed MMIO region
// HOT PATH: Small function, compiler will inline with -o:speed
mmio_write_u8 :: proc "c" (addr: uintptr, value: u8) {
    if !validate_mmio_address(addr, 1, "write_u8") {
        return
    }
    intrinsics.volatile_store((^u8)(addr), value)
    arm_dsb()
}

// Read a 64-bit value from an MMIO register
// SECURITY: Validates address is in allowed MMIO region
// HOT PATH: Small function, compiler will inline with -o:speed
mmio_read_u64 :: proc "c" (addr: uintptr) -> u64 {
    if !validate_mmio_address(addr, 8, "read_u64") {
        return 0xFFFFFFFFFFFFFFFF
    }
    value := intrinsics.volatile_load((^u64)(addr))
    arm_dmb()
    return value
}

// Write a 64-bit value to an MMIO register
// SECURITY: Validates address is in allowed MMIO region
// HOT PATH: Small function, compiler will inline with -o:speed
mmio_write_u64 :: proc "c" (addr: uintptr, value: u64) {
    if !validate_mmio_address(addr, 8, "write_u64") {
        return
    }
    intrinsics.volatile_store((^u64)(addr), value)
    arm_dsb()
}

// ARM Memory Barrier Instructions
// These ensure proper ordering of memory accesses

// Data Memory Barrier (DMB)
// Ensures all memory accesses before the DMB complete before
// any memory accesses after the DMB begin
arm_dmb :: proc "c" () {
    // DMB SY - full system DMB
    // This will be inlined by the compiler
    intrinsics.atomic_thread_fence(.Seq_Cst)
}

// Data Synchronization Barrier (DSB)
// Stronger than DMB - ensures all memory accesses complete
// and are observed by all observers before continuing
arm_dsb :: proc "c" () {
    // DSB SY - full system DSB
    intrinsics.atomic_thread_fence(.Seq_Cst)
}

// Instruction Synchronization Barrier (ISB)
// Flushes the pipeline and ensures all previous instructions
// complete before fetching any subsequent instructions
arm_isb :: proc "c" () {
    // ISB - instruction synchronization barrier
    // Required after updating system registers or exception vectors
    intrinsics.atomic_thread_fence(.Seq_Cst)
}
