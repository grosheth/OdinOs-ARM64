package kernel

// ARM64 Page Table Management
//
// Implements 4-level page tables with 4KB granule for ARMv8-A
// Supports 48-bit virtual addresses
//
// Page Table Hierarchy:
//  Level 0 (PGD): 512GB per entry
//  Level 1 (PUD): 1GB per entry
//  Level 2 (PMD): 2MB per entry (we'll use block descriptors here)
//  Level 3 (PTE): 4KB per entry

// Page table descriptor types
PTE_TYPE_FAULT  :: 0b00     // Invalid entry
PTE_TYPE_TABLE  :: 0b11     // Points to next level table
PTE_TYPE_BLOCK  :: 0b01     // Block descriptor (Level 1/2 only)
PTE_TYPE_PAGE   :: 0b11     // Page descriptor (Level 3 only)

// Descriptor bit definitions
PTE_VALID       :: (1 << 0)  // Descriptor is valid

// Block/Page attributes
PTE_ATTR_INDEX_SHIFT :: 2
PTE_MAIR_NORMAL      :: (0 << PTE_ATTR_INDEX_SHIFT)  // Normal memory (index 0)
PTE_MAIR_DEVICE      :: (1 << PTE_ATTR_INDEX_SHIFT)  // Device memory (index 1)

PTE_NS          :: (1 << 5)  // Non-secure
PTE_AP_RW       :: (0 << 6)  // Read/write, privileged only
PTE_AP_RO       :: (2 << 6)  // Read-only, privileged only
PTE_SH_INNER    :: (3 << 8)  // Inner shareable
PTE_AF          :: (1 << 10) // Access flag (must be 1)
PTE_NG          :: (1 << 11) // Not global

// Block/Page execution permissions (for ARMv8.1+, but safe to set)
PTE_UXN         :: (1 << 54) // Unprivileged execute never
PTE_PXN         :: (1 << 53) // Privileged execute never

// Page table entry type
Page_Table_Entry :: u64

// Page table (512 entries of 8 bytes = 4KB)
Page_Table :: struct #align(4096) {
    entries: [512]Page_Table_Entry,
}

// Static page tables (allocated in BSS)
// For initial boot, we'll use identity mapping with 2MB blocks
// This requires: 1 L0 table, 1 L1 table, 1 L2 table

// These will be placed in BSS and zeroed during boot
page_tables_l0: Page_Table  // Level 0 (covers 512GB)
page_tables_l1: Page_Table  // Level 1 (covers 512GB)
page_tables_l2: Page_Table  // Level 2 (covers 1GB using 512 × 2MB blocks)

// Initialize page tables (zero them - already done by BSS)
init_page_tables :: proc "c" () {
    // Tables are already zeroed by boot.s
    // Nothing to do here
}

// Create a page table entry pointing to next level
make_table_entry :: proc "c" (next_table_addr: u64) -> Page_Table_Entry {
    return Page_Table_Entry(next_table_addr | PTE_TYPE_TABLE | PTE_VALID)
}

// Create a 2MB block descriptor
make_block_entry :: proc "c" (physical_addr: u64, is_device: bool, executable: bool) -> Page_Table_Entry {
    entry := physical_addr | PTE_TYPE_BLOCK | PTE_VALID | PTE_AF | PTE_SH_INNER

    if is_device {
        // Device memory: non-cacheable, strongly ordered
        entry |= PTE_MAIR_DEVICE
        entry |= PTE_PXN | PTE_UXN  // Never executable
    } else {
        // Normal memory: write-back cacheable
        entry |= PTE_MAIR_NORMAL
        if !executable {
            entry |= PTE_PXN | PTE_UXN  // Not executable
        }
    }

    // Always R/W for kernel
    entry |= PTE_AP_RW

    return Page_Table_Entry(entry)
}

// Map a 2MB-aligned virtual address to physical address
// This is a simplified version that uses 2MB blocks
map_2mb_block :: proc "c" (virt_addr: u64, phys_addr: u64, is_device: bool, executable: bool) {
    // Extract page table indices from virtual address
    // For 4KB granule with 48-bit VA:
    // Bits [47:39] = L0 index (9 bits)
    // Bits [38:30] = L1 index (9 bits)
    // Bits [29:21] = L2 index (9 bits)
    // Bits [20:12] = L3 index (9 bits) - not used for 2MB blocks
    // Bits [11:0]  = Offset

    l0_idx := (virt_addr >> 39) & 0x1FF
    l1_idx := (virt_addr >> 30) & 0x1FF
    l2_idx := (virt_addr >> 21) & 0x1FF

    // Set up L0 entry to point to L1 table (if not already set)
    if page_tables_l0.entries[l0_idx] == 0 {
        l1_addr := u64(uintptr(&page_tables_l1))
        page_tables_l0.entries[l0_idx] = make_table_entry(l1_addr)
    }

    // Set up L1 entry to point to L2 table (if not already set)
    if page_tables_l1.entries[l1_idx] == 0 {
        l2_addr := u64(uintptr(&page_tables_l2))
        page_tables_l1.entries[l1_idx] = make_table_entry(l2_addr)
    }

    // Set up L2 entry as a 2MB block descriptor
    phys_aligned := phys_addr & ~u64(0x1FFFFF)  // Align to 2MB
    page_tables_l2.entries[l2_idx] = make_block_entry(phys_aligned, is_device, executable)
}

// Map a range of memory with 2MB blocks
map_range :: proc "c" (virt_start: u64, phys_start: u64, size: u64, is_device: bool, executable: bool) {
    // Align addresses to 2MB
    virt := virt_start & ~u64(0x1FFFFF)
    phys := phys_start & ~u64(0x1FFFFF)
    end := (virt_start + size + 0x1FFFFF) & ~u64(0x1FFFFF)

    // Map each 2MB block
    for virt < end {
        map_2mb_block(virt, phys, is_device, executable)
        virt += 0x200000  // 2MB
        phys += 0x200000
    }
}
