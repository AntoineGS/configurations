# MOSFET Power Switch Solution for PMW3610 Battery Drain

**Date:** 2025-12-19  
**Issue:** PMW3610 trackball consuming 1.95mA in deep sleep due to SPI bus remaining powered  
**Solution:** Hardware power switch using P-channel MOSFET controlled by GPIO

---

## Problem Summary

The nRF52840's SPI peripheral cannot be fully powered down at runtime without `status = "disabled"` in devicetree. Even with the PMW3610 in shutdown mode, the SPI bus leaks ~1.75mA to the sensor through VDD/signal lines.

**Current State:**
- Deep sleep power: 1.95mA
- Battery life: ~12 days
- Software solutions tested: ALL FAILED

**Root Cause:** SPI peripheral hardware remains powered → provides power rails → sensor draws current

---

## Solution Overview

Add a **P-channel MOSFET** to physically disconnect VDD power to the PMW3610 sensor during deep sleep. The nRF52840 controls the MOSFET via GPIO.

### Expected Results
- **Deep sleep power**: 0.20mA (confirmed by `status = "disabled"` test)
- **Battery life**: ~115 days (5x improvement)
- **Active power**: 1.95mA (unchanged)

---

## Hardware Implementation

### Required Components

| Component | Value/Part | Quantity | Cost | Notes |
|-----------|------------|----------|------|-------|
| P-Channel MOSFET | AO3401A (SOT-23) | 1 | $0.20 | Vds≥20V, Id≥1A |
| Pull-up resistor | 10kΩ (0603/0805) | 1 | $0.05 | Gate to Source |
| Gate resistor (optional) | 100Ω (0603/0805) | 1 | $0.05 | Reduces switching noise |
| Wire | 30AWG | ~10cm | - | For GPIO connection |

**Alternative MOSFETs:**
- Si2301DS (SOT-23) - Similar specs
- BSS84 (SOT-23) - Lower current, still sufficient
- Any P-MOSFET with Vgs(th) < 2V, Id > 100mA

### Circuit Schematic

```
                         3.3V Supply (from nRF52840)
                              |
                              |
                         [Source]
                            |
                        P-MOSFET (AO3401A)
                            |
                         [Drain] ──────────> PMW3610 VDD Pin
                            
    Available GPIO ─────[100Ω]────[Gate]
    (e.g., P1.06)                   |
                                 [10kΩ]
                                    |
                                   GND
```

**P-Channel MOSFET Logic:**
- GPIO **LOW (0V)** → Gate pulled to GND → Vgs = -3.3V → MOSFET **ON** → Sensor powered ✅
- GPIO **HIGH (3.3V)** → Gate = Source → Vgs = 0V → MOSFET **OFF** → Sensor unpowered ✅

### Physical Soldering Locations

#### Location 1: PMW3610 Module VDD Trace (Recommended)

**Where to Cut:**
Find the VDD trace connecting to the PMW3610 sensor on your trackball breakout board.

```
    [nRF52840 3.3V Rail]
            |
            | <- CUT HERE with hobby knife
            |    (between MCU and sensor)
            v
    [PMW3610 VDD Pin]
```

**Soldering Points:**

1. **Cut the VDD trace** near the sensor with sharp hobby knife
2. **Solder MOSFET Source** to the 3.3V side (MCU side)
3. **Solder MOSFET Drain** to the sensor side (PMW3610 VDD)
4. **Solder 10kΩ resistor** between Gate and Source (close to MOSFET)
5. **Solder 100Ω resistor** between GPIO wire and Gate
6. **Run wire** from Gate (through 100Ω) to available GPIO pad

#### Location 2: Sensor Module Direct (If accessible)

If your PMW3610 is on a separate breakout module:

```
Breakout Board:          MOSFET on Perfboard:       Sensor Module:
    [3.3V pad]  ───────>  [Source]──[Drain]  ─────>  [VDD pin]
                              [Gate]
                                |
                             [10kΩ to GND]
                                |
                          [Wire to GPIO]
```

**Method:**
1. Don't connect VDD wire from breakout to sensor
2. Build MOSFET circuit on tiny perfboard (5mm x 5mm)
3. Wire: Breakout 3.3V → MOSFET → Sensor VDD
4. Run gate control wire to nRF52840 GPIO

### Available GPIO Pins

Your Keyball44 Right configuration uses these pins:

**Already Used:**
- P0.04-P0.09: Matrix columns (pro_micro 4-9)
- P1.13: SPI1 SCK
- P0.10: SPI1 MOSI/MISO
- P0.09: SPI1 CS
- P1.11: PMW3610 IRQ

**Potentially Available (verify with your schematic):**
- **P1.06** - Adjacent to IRQ, easy routing
- **P1.12** - Near SPI pins
- **P1.14** - Available
- **P1.15** - Available
- **P0.02** - Available
- **P0.03** - Available

**Recommendation:** Use **P1.06** if available - it's physically close to the trackball area.

### Soldering Steps

1. **Identify VDD trace** on trackball module/PCB
   - Use multimeter continuity mode
   - Trace from PMW3610 VDD pin to 3.3V rail

2. **Mark cut location** with marker
   - Choose spot with good access
   - Far enough from sensor for MOSFET placement

3. **Cut trace cleanly**
   - Use sharp hobby knife
   - Score multiple times, don't force
   - Verify cut with multimeter (no continuity)

4. **Prepare MOSFET** (SOT-23 package)
   ```
   SOT-23 Pinout (looking at top, pins down):
   
       Pin 1: Gate
       Pin 2: Source  
       Pin 3: Drain
   
       [1] [2] [3]
          \_|_/
            |
   ```

5. **Solder MOSFET**
   - Source (pin 2) to MCU side of cut trace
   - Drain (pin 3) to sensor side of cut trace
   - Use flux and fine tip iron (300°C)

6. **Solder 10kΩ pull-up**
   - One end to Gate (pin 1)
   - Other end to Source (pin 2)

7. **Solder 100Ω gate resistor** (optional but recommended)
   - One end to Gate (pin 1)
   - Other end: leave wire for GPIO connection

8. **Run wire to GPIO**
   - 30AWG wire from 100Ω resistor to GPIO pad
   - Secure with hot glue or kapton tape

9. **Test before reassembly**
   - Power on keyboard
   - Measure voltage at sensor VDD with multimeter
   - Should be 3.3V initially

---

## Software Implementation

### Step 1: Update Devicetree

**File:** `boards/shields/keyball44/keyball44_right.overlay`

Add regulator node before `&spi1` section:

```dts
/ {
    trackball_power: trackball-power {
        compatible = "regulator-fixed";
        regulator-name = "trackball-vdd";
        enable-gpios = <&gpio1 10 GPIO_ACTIVE_LOW>;  // P1.06, P-MOSFET: LOW=ON
        regulator-boot-on;  // Start powered ON at boot
        startup-delay-us = <1000>;  // 1ms power-on delay
    };
};
```

**Note:** Change `<&gpio1 10 ...>` to match your chosen GPIO pin.

### Step 2: Link Sensor to Power Supply

Modify the trackball node in same file:

```dts
&trackball {
    status = "okay";
    compatible = "pixart,pmw3610";
    reg = <0>;
    spi-max-frequency = <2000000>;
    irq-gpios = <&gpio1 11 (GPIO_ACTIVE_LOW | GPIO_PULL_UP)>;
    scroll-layers = <4>;
    vin-supply = <&trackball_power>;  // ADD THIS LINE
};
```

### Step 3: Create Power Control Module

**File:** `~/gits/zmk/app/src/trackball_power.c` (new file)

```c
/*
 * Copyright (c) 2025 ZMK Contributors
 *
 * SPDX-License-Identifier: MIT
 */

#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/regulator.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(trackball_power, CONFIG_ZMK_LOG_LEVEL);

#define TRACKBALL_POWER_NODE DT_PATH(trackball_power)

#if DT_NODE_HAS_STATUS(TRACKBALL_POWER_NODE, okay)

static const struct device *trackball_power_dev = DEVICE_DT_GET(TRACKBALL_POWER_NODE);

int trackball_power_on(void) {
    if (!device_is_ready(trackball_power_dev)) {
        LOG_ERR("Trackball power device not ready");
        return -ENODEV;
    }
    
    int ret = regulator_enable(trackball_power_dev);
    if (ret < 0) {
        LOG_ERR("Failed to enable trackball power: %d", ret);
        return ret;
    }
    
    LOG_INF("Trackball power ON");
    
    // Wait for sensor power stabilization
    k_msleep(10);
    
    return 0;
}

int trackball_power_off(void) {
    if (!device_is_ready(trackball_power_dev)) {
        LOG_ERR("Trackball power device not ready");
        return -ENODEV;
    }
    
    int ret = regulator_disable(trackball_power_dev);
    if (ret < 0) {
        LOG_ERR("Failed to disable trackball power: %d", ret);
        return ret;
    }
    
    LOG_INF("Trackball power OFF");
    
    return 0;
}

static int trackball_power_init(void) {
    if (!device_is_ready(trackball_power_dev)) {
        LOG_ERR("Trackball power device not ready");
        return -ENODEV;
    }
    
    LOG_INF("Trackball power control initialized");
    return 0;
}

SYS_INIT(trackball_power_init, APPLICATION, CONFIG_APPLICATION_INIT_PRIORITY);

#endif /* DT_NODE_HAS_STATUS */
```

### Step 4: Add to CMakeLists

**File:** `~/gits/zmk/app/CMakeLists.txt`

Add after other source files:

```cmake
target_sources(app PRIVATE src/trackball_power.c)
```

### Step 5: Integrate with Power Management

**File:** `~/gits/zmk/app/src/activity.c`

Add the header near the top:

```c
// Add with other includes
extern int trackball_power_on(void);
extern int trackball_power_off(void);
```

Modify the sleep handler (find `zmk_activity_sleep` or similar):

```c
static void activity_sleep_timeout(struct k_work *work) {
    // ... existing sleep preparation code ...
    
    #ifdef CONFIG_ZMK_TRACKBALL_POWER_CONTROL
    // Power off trackball before deep sleep
    trackball_power_off();
    #endif
    
    // ... rest of sleep code ...
}
```

Modify the wake handler:

```c
static void activity_wake(void) {
    #ifdef CONFIG_ZMK_TRACKBALL_POWER_CONTROL
    // Power on trackball after wake
    trackball_power_on();
    #endif
    
    // ... rest of wake code ...
}
```

### Step 6: Add Kconfig Option

**File:** `~/gits/zmk/app/Kconfig`

Add configuration option:

```kconfig
config ZMK_TRACKBALL_POWER_CONTROL
    bool "Trackball Power Control"
    depends on REGULATOR
    help
      Enable GPIO-controlled power switching for trackball sensor.
      Reduces deep sleep current by completely powering off the sensor.
```

### Step 7: Enable in Build Configuration

**File:** `config/keyball44_right.conf` (in your zmk-config repo)

Add:

```
CONFIG_ZMK_TRACKBALL_POWER_CONTROL=y
CONFIG_REGULATOR=y
```

---

## Testing Procedure

### Phase 1: Hardware Verification (Before Software)

1. **Continuity Test**
   - Verify VDD trace is cut (no continuity)
   - Verify MOSFET Source connects to 3.3V
   - Verify MOSFET Drain connects to sensor VDD

2. **Resistance Test** (powered off)
   - Gate to Source: Should read ~10kΩ (pull-up resistor)
   - Source to Drain: Should be high impedance (MΩ)

3. **Initial Power Test** (GPIO floating)
   - Power on keyboard
   - Measure sensor VDD: Should be 0V (MOSFET OFF due to pull-up)
   
   **IMPORTANT:** If sensor VDD is 3.3V with GPIO floating, MOSFET is wired backward!

### Phase 2: Manual GPIO Control

Before integrating with ZMK, test GPIO control manually:

```c
// Test code to add temporarily
#include <zephyr/drivers/gpio.h>

const struct device *gpio_dev = DEVICE_DT_GET(DT_NODELABEL(gpio1));
gpio_pin_configure(gpio_dev, 10, GPIO_OUTPUT);

// Test ON
gpio_pin_set(gpio_dev, 10, 0);  // LOW = ON
k_msleep(100);
// Measure sensor VDD: Should be 3.3V

// Test OFF
gpio_pin_set(gpio_dev, 10, 1);  // HIGH = OFF
k_msleep(100);
// Measure sensor VDD: Should be 0V
```

### Phase 3: Current Consumption Test

1. **Build firmware** with power control enabled
2. **Flash to keyboard**
3. **Measure current** with multimeter in series with battery
4. **Wait for deep sleep** (15 minutes default)
5. **Verify current drops to ~0.20mA**

**Success Criteria:**
- Active: 1.5-2.0mA (with trackball working)
- Deep sleep: 0.15-0.25mA ✅

### Phase 4: Functional Test

1. **Test trackball after wake**
   - Move trackball, verify cursor moves
   - Test scroll mode
   - Verify no sensor errors in logs

2. **Test sleep/wake cycle**
   - Enter sleep (wait 15 min)
   - Wake with key press
   - Verify trackball works immediately

3. **Stress test**
   - Multiple sleep/wake cycles
   - Leave in sleep overnight
   - Verify no issues

---

## Troubleshooting

### Issue: Sensor VDD always 3.3V (doesn't turn off)

**Cause:** MOSFET wired backward or wrong type

**Fix:**
- Verify P-channel MOSFET (not N-channel)
- Check pinout: Source to 3.3V, Drain to sensor
- Verify GPIO goes HIGH to turn off

### Issue: Sensor VDD always 0V (doesn't turn on)

**Cause:** Pull-up resistor missing or GPIO stuck HIGH

**Fix:**
- Verify 10kΩ resistor between Gate and Source
- Check GPIO is set LOW during boot
- Verify `regulator-boot-on` in devicetree

### Issue: Trackball doesn't work after wake

**Cause:** Sensor not reinitializing properly

**Fix:**
- Increase `startup-delay-us` to 5000 (5ms)
- Add re-initialization delay in `trackball_power_on()`:
  ```c
  k_msleep(50);  // Longer delay for sensor boot
  ```

### Issue: Current still high in sleep (>0.5mA)

**Cause:** SPI bus not releasing sensor, or other power drain

**Fix:**
- Verify sensor VDD is actually 0V in sleep
- Check other peripherals (display, LEDs)
- Measure current with trackball physically disconnected

### Issue: GPIO conflict or not available

**Cause:** Pin already used by another feature

**Fix:**
- Check your board schematic carefully
- Try different GPIO pin
- May need to sacrifice a feature to free a pin

---

## Alternative: N-Channel MOSFET (Low-Side Switch)

If cutting GND trace is easier than VDD:

### Circuit

```
PMW3610 GND ───[Drain] N-MOSFET [Source]─── GND
                       [Gate]
                         |
                       [10kΩ to GND]
                         |
                    [100Ω from GPIO]
```

### Components
- N-Channel MOSFET: AO3400A, 2N7002, BSS138
- Same resistor values

### Logic
- GPIO **HIGH** → MOSFET ON → Sensor powered ON ✅
- GPIO **LOW** → MOSFET OFF → Sensor powered OFF ✅

### Devicetree Change
```dts
enable-gpios = <&gpio1 10 GPIO_ACTIVE_HIGH>;  // N-MOSFET: HIGH=ON
```

**Note:** Low-side switching is less common but works equally well for power savings.

---

## Bill of Materials

| Item | Part Number | Quantity | Unit Price | Total | Source |
|------|-------------|----------|------------|-------|--------|
| P-MOSFET | AO3401A (SOT-23) | 1 | $0.20 | $0.20 | Digikey, LCSC |
| Resistor 10kΩ | 0603/0805 SMD | 1 | $0.02 | $0.02 | Digikey, LCSC |
| Resistor 100Ω | 0603/0805 SMD | 1 | $0.02 | $0.02 | Digikey, LCSC |
| Wire 30AWG | Kynar wire | 10cm | $0.10 | $0.10 | Amazon, Digikey |
| **TOTAL** | | | | **$0.34** | |

**Tool Requirements:**
- Soldering iron (fine tip, temperature controlled)
- Flux (rosin-based)
- Solder (63/37 leaded or SAC305 lead-free)
- Hobby knife (for cutting trace)
- Multimeter
- Tweezers (for SMD components)
- Magnifying glass/microscope (optional but helpful)

---

## Estimated Implementation Time

- **Hardware mod**: 30-60 minutes (careful soldering)
- **Software implementation**: 1-2 hours (coding + testing)
- **Testing & verification**: 30 minutes
- **Total**: 2-3 hours

---

## Conclusion

This hardware modification provides the **only reliable solution** for achieving <0.25mA deep sleep current with the PMW3610 trackball enabled. 

While it requires careful soldering and adding ZMK code, the 5x battery life improvement (12 days → 115 days) makes it worthwhile for users who need maximum battery efficiency.

**Risk Assessment:** Low - Modification is reversible, components are cheap, failure modes are safe (worst case: trackball doesn't work, keyboard functions normally).

---

## References

- [PMW3610 Shutdown Investigation](./PMW3610_SHUTDOWN_INVESTIGATION.md)
- [Battery Drain Investigation](./BATTERY_DRAIN_INVESTIGATION.md)
- [Zephyr Regulator API](https://docs.zephyrproject.org/latest/hardware/peripherals/regulator.html)
- [AO3401A Datasheet](https://www.aosmd.com/res/data_sheets/AO3401A.pdf)
