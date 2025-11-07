/* OdinOS Linker Script - ARM64 */
/* Target: iPhone 7 (A10 Fusion) - ARMv8-A */

/* Entry point */
ENTRY(_start)

/* Memory layout for ARM64 */
/* QEMU virt machine loads at 0x40000000 */
/* Real iPhone 7 varies - adjust based on device tree */
MEMORY
{
    /* RAM: Starting at 0x40000000 for QEMU virt */
    RAM (rwx) : ORIGIN = 0x40000000, LENGTH = 128M
}

SECTIONS
{
    . = 0x40000000;  /* Load address */

    /* Text section - executable code */
    .text : ALIGN(4K)
    {
        KEEP(*(.text.boot))  /* Boot code first */
        *(.text*)
    } > RAM

    /* Read-only data */
    .rodata : ALIGN(4K)
    {
        *(.rodata*)
    } > RAM

    /* Initialized data */
    .data : ALIGN(4K)
    {
        *(.data*)
    } > RAM

    /* BSS section - uninitialized data (zeroed) */
    .bss : ALIGN(4K)
    {
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    } > RAM

    /* Stack (grows downward) */
    .stack : ALIGN(4K)
    {
        . = . + 0x4000;  /* 16KB stack */
        __stack_top = .;
    } > RAM

    /* Kernel end marker */
    __kernel_end = .;

    /* Discard sections we don't need */
    /DISCARD/ :
    {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
    }
}
