# OdinOS - iPhone 7 ARM64 Kernel

A bare-metal kernel for iPhone 7 (Apple A10 Fusion) written in Odin programming language.

## Target Hardware

- **Device**: iPhone 7 (iPhone9,1 / iPhone9,3)
- **SoC**: Apple A10 Fusion
- **Architecture**: ARMv8-A (64-bit ARM)
- **Cores**: 2x Hurricane (high-performance) + 2x Zephyr (efficiency)
- **Boot method**: checkra1n / checkm8 exploit chain

## Project Structure

```
OdinOs-ARM64/
├── .claude/              # AI agent configurations
│   └── prompts/          # Specialized agents for development
├── src/                  # Source code
│   ├── boot/            # Boot assembly and initialization
│   ├── drivers/         # Device drivers (UART, framebuffer, etc.)
│   ├── mm/              # Memory management
│   └── linker.ld        # Linker script
├── build/               # Build artifacts (generated)
├── shell.nix            # Nix development environment
├── Makefile             # Build system
└── README.md            # This file
```

## Development Environment

### Using Nix (Recommended for NixOS)

```bash
# Enter the development shell
nix-shell

# This provides:
# - Odin compiler with ARM64 support
# - ARM64 cross-compilation toolchain
# - QEMU for ARM64 emulation
# - Device tree tools
# - GDB for debugging
```

### Manual Setup

Requirements:
- Odin compiler (with ARM64 target support)
- ARM64 cross-compiler (aarch64-unknown-linux-gnu-gcc)
- QEMU (qemu-system-aarch64)
- GNU Make
- Device Tree Compiler (dtc)

## Building

```bash
# Build the kernel
make

# Build and run in QEMU
make run

# Build and debug with GDB
make debug

# Show kernel information
make info

# Clean build artifacts
make clean
```

## Development Workflow

### 1. Plan Your Work

Use the planner agent to break down tasks:
- Features are decomposed into atomic tasks
- Dependencies are identified
- Risk assessment is performed

### 2. Implement

The coder agent helps with:
- ARM64-specific code patterns
- MMIO (Memory-Mapped I/O) operations
- Exception handling
- Device tree parsing

### 3. Optimize

The optimizer agent reviews for:
- ARM64 performance optimizations
- Cache-friendly memory access
- NEON SIMD opportunities
- A10 Fusion-specific tuning

### 4. Security Review

The security agent audits for:
- Memory safety issues
- Privilege escalation risks
- MMIO security concerns
- ARM-specific vulnerabilities

## Getting Started

### Quick Start

1. Enter development environment:
```bash
nix-shell  # Or ensure ARM64 toolchain is installed
```

2. Build the kernel:
```bash
make
```

3. Run in QEMU:
```bash
make run
```

4. Expected output:
```
========================================
   OdinOS ARM64 v0.1
   Target: Apple iPhone 7 (A10 Fusion)
========================================

[1/5] UART initialized
[2/5] Device tree parsing - TODO
[3/5] Installing exception vectors... done
[4/5] Setting up MMU and page tables
  - Mapping kernel (0x40000000-0x48000000)... ok
  - Mapping UART (0x09000000)... ok
  - Configuring MAIR... ok
  - Configuring TCR... ok
  - Setting TTBR0... ok
  - Enabling MMU... ok
[4/5] MMU enabled successfully!

OdinOS boot complete!
System is now halting...
```

### Build Targets

- `make` - Build the kernel
- `make run` - Run in QEMU
- `make debug` - Run with GDB server
- `make verify` - Verify build symbols
- `make test` - Run automated boot test
- `make clean` - Clean build artifacts

## Architecture Overview

### Boot Process

1. iBoot loads kernel at specified address
2. ARM64 starts in EL2 (hypervisor) or EL1 (kernel)
3. Boot assembly sets up initial stack
4. Jump to Odin `kernel_main`
5. Initialize hardware via device tree
6. Set up exception vectors
7. Enable MMU and page tables
8. Start scheduler (future)

### Memory Layout

```
0x40000000 - Kernel code (.text)
           - Read-only data (.rodata)
           - Initialized data (.data)
           - BSS (zero-initialized)
           - Stack (16KB)
           - Heap (future)
```

### Key Subsystems

#### Implemented ✓
- [x] Boot assembly (EL1/EL2 detection)
- [x] UART driver (PL011, serial debugging)
- [x] MMIO helpers (volatile memory access)
- [x] Exception/interrupt handling (16-entry vector table)
- [x] Memory management (MMU, 4-level page tables, identity mapping)
- [x] Page tables (4KB granule, 2MB blocks)
- [x] Caching (I-cache, D-cache enabled)

#### Planned
- [ ] Device tree parser
- [ ] GIC (Generic Interrupt Controller)
- [ ] Timer driver
- [ ] Framebuffer driver (display output)
- [ ] Dynamic page allocation
- [ ] User mode support (EL0)
- [ ] Basic scheduler
- [ ] Syscall interface

## Testing

### QEMU

The kernel can be tested in QEMU's ARM64 virt machine:

```bash
make run
```

Note: QEMU's virt machine is different from real iPhone 7 hardware.
Some drivers will need adaptation for real hardware.

### Real Hardware (iPhone 7)

⚠️ **CRITICAL WARNING**: Installing a custom kernel on iPhone 7 carries significant risks:
- **Potential to brick your device** - Recovery may be impossible
- **Voids warranty** (if applicable)
- **No Apple support** if something goes wrong
- **Data loss risk** - Back up everything first
- **Experimental software** - Many features are not implemented

**Only proceed if you:**
- Understand ARM64 bare-metal development
- Have experience with checkra1n/checkm8
- Accept full responsibility for any damage
- Have a backup device available

---

#### Prerequisites

**Hardware Required:**
- iPhone 7 or iPhone 7 Plus (iPhone9,1 or iPhone9,3)
- USB-A to Lightning cable (USB-C may not work reliably with checkra1n)
- Linux or macOS computer (checkra1n doesn't support Windows natively)
- (Optional but recommended) USB serial debug cable (e.g., Kong USB-C to 3.3V UART)

**Software Required:**
- [checkra1n](https://checkra.in/) v0.12.0 or later
- `iproxy` from libusbmuxd (for USB forwarding)
- `scp` or similar file transfer tool

**Skills Required:**
- Understanding of iOS boot process
- Familiarity with command line tools
- Ability to recover from boot loops (DFU mode recovery)

---

#### Installation Steps

##### Step 1: Prepare Your iPhone 7

1. **Backup everything** - Use iTunes or iCloud to create a full backup

2. **Update to compatible iOS version**:
   - checkra1n works best on iOS 12.x - 14.x
   - Newer versions may require updated checkra1n

3. **Disable passcode and Find My iPhone**:
   ```
   Settings → Face ID & Passcode → Turn Passcode Off
   Settings → [Your Name] → Find My → Find My iPhone → Off
   ```

4. **Ensure battery is charged** (>50% recommended)

##### Step 2: Jailbreak with checkra1n

1. **Download checkra1n** from https://checkra.in/

2. **Run checkra1n** (on Linux, may require sudo):
   ```bash
   # Linux
   sudo ./checkra1n

   # macOS
   open checkra1n.app
   ```

3. **Follow checkra1n prompts**:
   - Click "Start"
   - Put iPhone into DFU mode when prompted:
     1. Connect iPhone to computer
     2. Press and hold Power + Volume Down for 10 seconds
     3. Release Power, keep holding Volume Down for 5 more seconds
     4. Screen should stay black (if Apple logo appears, retry)

4. **Wait for jailbreak to complete** (~1-2 minutes)

5. **iPhone will reboot** - checkra1n loader should appear

6. **Open checkra1n app on iPhone** and install Cydia (if desired for debugging tools)

##### Step 3: Install SSH Access

1. **Open checkra1n app** on iPhone
2. **Install SSH** toggle (enabled by default in recent versions)
3. **Note the iPhone's IP address** (Settings → Wi-Fi → (i) next to network)

Alternatively, install OpenSSH via Cydia:
```bash
# On iPhone (via checkra1n terminal or Cydia)
apt-get update
apt-get install openssh
```

Default credentials:
- Username: `root`
- Password: `alpine` (⚠️ Change this immediately!)

##### Step 4: Build OdinOS for iPhone 7

1. **Build the kernel**:
   ```bash
   make clean
   make
   ```

2. **Verify the kernel** was built correctly:
   ```bash
   make verify
   file build/kernel.bin
   ```

   Should show: `build/kernel.bin: data`

##### Step 5: Transfer Kernel to iPhone

1. **Set up USB forwarding** (if using USB connection):
   ```bash
   # Forward SSH port via USB
   iproxy 2222 44 &
   ```

2. **Copy kernel to iPhone**:
   ```bash
   # Via USB (using iproxy)
   scp -P 2222 build/kernel.bin root@localhost:/var/mobile/

   # Via Wi-Fi
   scp build/kernel.bin root@<IPHONE_IP>:/var/mobile/
   ```

3. **Enter password** when prompted (default: `alpine`)

##### Step 6: Prepare Custom Boot Configuration

⚠️ **THIS IS THE DANGEROUS PART** - Triple-check everything!

1. **SSH into iPhone**:
   ```bash
   # Via USB
   ssh -p 2222 root@localhost

   # Via Wi-Fi
   ssh root@<IPHONE_IP>
   ```

2. **Locate the boot partition** (varies by iOS version):
   ```bash
   # Check mounted filesystems
   mount | grep -E "(disk0s1s1|disk0s1s2)"

   # Typically:
   # /dev/disk0s1s1 - Boot partition
   # /dev/disk0s1s2 - System partition
   ```

3. **Mount boot partition** (if not already mounted):
   ```bash
   # Create mount point
   mkdir -p /mnt/boot

   # Mount (adjust device name if different)
   mount -t hfs /dev/disk0s1s1 /mnt/boot
   ```

4. **Backup original iBoot files**:
   ```bash
   # CRITICAL: Create backups!
   cp /mnt/boot/iBEC /mnt/boot/iBEC.backup
   cp /mnt/boot/iBSS /mnt/boot/iBSS.backup
   cp /mnt/boot/kernelcache /mnt/boot/kernelcache.backup
   ```

5. **Copy OdinOS kernel**:
   ```bash
   # Copy kernel to boot partition
   cp /var/mobile/kernel.bin /mnt/boot/odinos.bin
   ```

##### Step 7: Configure Bootloader (Advanced)

⚠️ **EXPERT-LEVEL ONLY** - This requires deep understanding of iOS boot process!

**Option A: checkra1n Boot Script (Safer)**

Create a boot script that loads OdinOS via checkra1n:

```bash
cat > /var/mobile/boot_odinos.sh << 'EOF'
#!/bin/bash
# Load OdinOS kernel via checkm8 exploit

# Load kernel at 0x40000000 (as configured in linker.ld)
/usr/bin/checkm8_loader \
    --load-address 0x40000000 \
    --kernel /var/mobile/kernel.bin \
    --jump-address 0x40000000
EOF

chmod +x /var/mobile/boot_odinos.sh
```

**Option B: Modify Device Tree (Very Advanced)**

This requires understanding of iOS device tree format and iBoot internals. **Not recommended** unless you have experience with iOS internals.

##### Step 8: Boot OdinOS

**Method 1: Manual Boot (Safer for Testing)**

1. **Reboot iPhone into checkra1n recovery mode**
2. **Use checkra1n CLI** to load OdinOS:
   ```bash
   # On your computer
   checkra1n --cli --load-kernel build/kernel.bin --load-address 0x40000000
   ```

**Method 2: Automatic Boot (Advanced)**

Requires modifying iBoot or using a custom bootloader. This is extremely advanced and beyond the scope of this guide.

---

#### Debugging on Real Hardware

**Serial Debug Output (Highly Recommended):**

1. **Acquire USB serial adapter** compatible with iPhone UART:
   - Commonly used: Kong USB-C to 3.3V UART adapter
   - Connect to iPhone 7 debug pads (requires soldering or special cable)

2. **iPhone 7 UART Pinout** (connector near Lightning port):
   - Pin 1: GND
   - Pin 2: UART_TX (output from iPhone)
   - Pin 3: UART_RX (input to iPhone)
   - Voltage: 1.8V or 3.3V (check your adapter)

3. **Connect serial adapter** and open terminal:
   ```bash
   # Linux
   screen /dev/ttyUSB0 115200

   # macOS
   screen /dev/cu.usbserial 115200
   ```

4. **Boot OdinOS** - You should see UART output:
   ```
   ========================================
      OdinOS ARM64 v0.1
      Target: Apple iPhone 7 (A10 Fusion)
   ========================================
   [1/5] UART initialized
   ...
   ```

---

#### Troubleshooting

**iPhone Won't Boot After Installing OdinOS:**

1. **Enter DFU Mode**:
   - Press and hold Power + Volume Down for 10 seconds
   - Release Power, keep holding Volume Down
   - Screen stays black

2. **Restore with iTunes/Finder**:
   - Connect to computer
   - iTunes/Finder will detect iPhone in recovery mode
   - Click "Restore iPhone"
   - ⚠️ This will erase all data!

3. **Re-jailbreak with checkra1n** if needed

**OdinOS Doesn't Output Anything:**

- Verify UART is connected correctly
- Check baud rate (should be 115200)
- Ensure kernel was loaded at correct address (0x40000000)
- Check that MMU didn't crash during initialization

**Kernel Crashes Immediately:**

- Verify linker script matches load address
- Check that device tree is being parsed correctly
- Ensure all hardware addresses are correct for iPhone 7
  - Note: iPhone 7 UART may be at different address than QEMU!
  - Use checkra1n to dump device tree: `ioreg -l -p IODeviceTree`

**Infinite Boot Loop:**

1. Enter DFU mode
2. Restore backups:
   ```bash
   cp /mnt/boot/kernelcache.backup /mnt/boot/kernelcache
   ```
3. Reboot

---

#### Current Limitations on Real Hardware

OdinOS v0.1 has **not been tested on real iPhone 7 hardware**. Known limitations:

- ❌ UART address is hardcoded for QEMU (0x09000000) - iPhone 7 will differ
- ❌ No device tree parser - won't discover iPhone 7 hardware automatically
- ❌ No framebuffer driver - no visual output
- ❌ No touch input support
- ❌ No storage driver - can't persist data
- ❌ No network support
- ❌ No power management - battery will drain quickly

**To make it work on iPhone 7, you need to:**

1. Dump the iPhone 7 device tree and find the UART base address
2. Update `QEMU_UART_BASE` in `src/kernel.odin` with the correct address
3. Implement device tree parser (see TODO-implementation.md)
4. Test extensively in QEMU first!

---

#### Recovery Plan

**If something goes wrong:**

1. **DFU Mode Recovery**:
   ```
   Power + Volume Down for 10 seconds
   Release Power, keep Volume Down for 5 seconds
   ```

2. **iTunes/Finder Restore**:
   - Will erase all data
   - Restores to latest iOS version
   - Cannot downgrade without SHSH blobs

3. **checkra1n Re-jailbreak**:
   - Usually works even after failed boots
   - May need to restore first

4. **Professional Help**:
   - Apple Store (will refuse to help with jailbroken device)
   - Third-party repair shop with microsoldering experience
   - iPhone data recovery services (expensive!)

---

#### Legal and Safety Notices

**Legal:**
- Jailbreaking may void your warranty
- Check local laws regarding device modification
- OdinOS is provided AS-IS with no warranty
- The developers are not responsible for any damage

**Safety:**
- Keep iPhone well-ventilated during testing
- Monitor temperature - custom kernels may not have thermal management
- Don't leave plugged in for extended periods
- Have a fire extinguisher nearby (lithium batteries can be dangerous)

**Privacy:**
- OdinOS has no networking stack - your data stays local
- However, SSH access (if enabled) could be a security risk
- Change default root password immediately!

---

#### Getting Help

**Before asking for help:**
- Read this guide completely
- Check that you followed all steps
- Verify your iPhone 7 model is supported
- Have serial debug output available

**Community Resources:**
- r/jailbreak - General jailbreaking help
- r/osdev - Operating system development
- iPhone Wiki - iPhone internals documentation
- checkra1in Discord - checkra1n-specific issues

**What to include in bug reports:**
- iPhone model (Settings → General → About → Model)
- iOS version
- checkra1n version
- Serial debug output (if available)
- Steps to reproduce the issue

---

**Remember: This is experimental software. Only install on a device you're willing to lose!**

## Resources

### ARM64 Documentation

- [ARM Architecture Reference Manual (ARMv8-A)](https://developer.arm.com/documentation)
- [ARM Cortex-A Series Programmer's Guide](https://developer.arm.com/documentation)
- [ARMv8-A Exception Handling](https://developer.arm.com/documentation)

### iPhone 7 Specific

- [checkra1n](https://checkra.in/) - Jailbreak tool
- [Project Sandcastle](https://projectsandcastle.org/) - Android on iPhone reference
- [iPhone Wiki](https://www.theiphonewiki.com/wiki/IPhone_7)

### Odin Language

- [Odin Language Documentation](https://odin-lang.org/docs/)
- [Odin GitHub](https://github.com/odin-lang/Odin)

## Contributing

This is a learning project. Contributions welcome!

Areas that need work:
- Device tree parser
- UART driver implementation
- MMU/page table setup
- Exception vector implementation
- Real hardware testing

## License

TBD

## Acknowledgments

- Odin programming language team
- checkra1n team for boot exploit
- ARM Ltd. for comprehensive documentation
- OSDev community for bare-metal development resources
