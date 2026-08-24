# ZMK Keyboard Firmware

**Location:** `Linux/zmk-config/keyball44/`

**Keyboards using ZMK:**

- `keyball44/` - Keyball 44 (44-key split with PMW3610 trackball)

**Build Environment:**

- ZMK firmware repository: `~/gits/zmk`
- Python virtual environment: `~/gits/zmk/.venv`
- Build system: West (Zephyr meta-tool)
- Module structure: Uses ZMK module pattern with `zephyr/module.yml`

**Build and Flash (Automated):**

```bash
# From the keyball44 config directory
cd ~/gits/configurations/Linux/zmk-config/keyball44

# Build and flash left side
./build_flash.sh left

# Build and flash right side
./build_flash.sh right
```

The script will:

- Build the firmware with pristine build (`-p` flag)
- Wait for you to double-tap the reset button
- Automatically detect and mount the Nice Nano
- Flash the firmware
- Sync and unmount

**Manual Build Commands (if needed):**

```bash
cd ~/gits/zmk
source .venv/bin/activate
cd app

# Build left side
west build -d build/left -b nice_nano_v2 -- -DSHIELD="keyball44_left nice_view_adapter nice_view_custom" -DZMK_CONFIG=/home/antoinegs/gits/configurations/Linux/zmk-config/keyball44

# Build right side (with PMW3610 trackball driver)
west build -d build/right -b nice_nano_v2 -- -DSHIELD="keyball44_right nice_view_adapter nice_view" -DZMK_CONFIG=/home/antoinegs/gits/configurations/Linux/zmk-config/keyball44
```

**Firmware Output:**

- Left: `~/gits/zmk/app/build/left/zephyr/zmk.uf2` (~544 KB)
- Right: `~/gits/zmk/app/build/right/zephyr/zmk.uf2` (~698 KB)

**Flashing:**

1. Double-tap reset button on Nice Nano to enter bootloader mode
1. Copy the `.uf2` file to the mounted USB drive
1. Board will automatically reboot with new firmware

**Important Notes:**

- The `-p` flag does a pristine build (clean rebuild)
- Remove `-p` for incremental builds after making small changes
- The right side is larger due to the PMW3610 trackball driver
- PMW3610 driver is fetched via West from kumamuk-git/zmk-pmw3610-driver

**Dependencies:**

- Zephyr SDK 0.16.3 installed at `~/zephyr-sdk-0.16.3`
- Python packages in venv: setuptools, protobuf, west
- CMake, dtc (device tree compiler), ninja-build

**Configuration Files:**

- `boards/shields/keyball44/keyball44.keymap` - Main keymap with layers,
  behaviors, and macros
- `boards/shields/keyball44/keyball44.conf` - Keyboard-level configuration (BLE,
  display, behaviors)
- `boards/shields/keyball44/keyball44_left.overlay` - Left side hardware
  definition
- `boards/shields/keyball44/keyball44_right.overlay` - Right side hardware
  definition
- `boards/shields/keyball44/keyball44_right.conf` - PMW3610 trackball
  configuration
- `config/west.yml` - West manifest for dependencies
- `zephyr/module.yml` - ZMK module definition

**Architecture details:** See `Linux/zmk-config/keyball44/CONFIG.md` for
detailed documentation on:

- Timeless homerow mods implementation (urob's pattern)
- 4-layer system (DEF/NAV/SYM/NUM with tri-layer)
- French character macros using US International dead keys
- PMW3610 trackball driver configuration
- Key position definitions for positional hold-tap
- Testing checklist and migration notes from QMK

**Troubleshooting:**

- If build fails with "unknown symbol PMW3610": Run `west update` to fetch
  driver modules
- If Python errors occur: Ensure `setuptools` and `protobuf` are installed in
  venv
- Devicetree errors: Check syntax in `.overlay` and `.keymap` files (use `,`
  between binding items)
