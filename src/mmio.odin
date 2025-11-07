package kernel

// MMIO (Memory-Mapped I/O) Helper Functions
//
// These functions provide type-safe, volatile access to hardware registers.
// They include proper memory barriers to ensure correct ordering of MMIO operations.
//
// SAFETY: These functions provide NO bounds checking or validation.
// The caller MUST ensure:
//  - The address is a valid MMIO region
//  - The address is properly aligned (4-byte for u32, 8-byte for u64)
//  - The hardware expects the access size being used

import "base:intrinsics"

// Read a 32-bit value from an MMIO register
// Uses volatile load to prevent compiler optimization
// Includes memory barrier to ensure ordering
mmio_read_u32 :: proc "c" (addr: uintptr) -> u32 {
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
mmio_write_u32 :: proc "c" (addr: uintptr, value: u32) {
    // Volatile store prevents compiler from optimizing away the write
    intrinsics.volatile_store((^u32)(addr), value)

    // DSB after write ensures the write completes before subsequent accesses
    // This is sufficient per ARM Architecture Reference Manual
    arm_dsb()
}

// Read an 8-bit value from an MMIO register
mmio_read_u8 :: proc "c" (addr: uintptr) -> u8 {
    value := intrinsics.volatile_load((^u8)(addr))
    arm_dmb()
    return value
}

// Write an 8-bit value to an MMIO register
mmio_write_u8 :: proc "c" (addr: uintptr, value: u8) {
    intrinsics.volatile_store((^u8)(addr), value)
    arm_dsb()
}

// Read a 64-bit value from an MMIO register
mmio_read_u64 :: proc "c" (addr: uintptr) -> u64 {
    value := intrinsics.volatile_load((^u64)(addr))
    arm_dmb()
    return value
}

// Write a 64-bit value to an MMIO register
mmio_write_u64 :: proc "c" (addr: uintptr, value: u64) {
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
