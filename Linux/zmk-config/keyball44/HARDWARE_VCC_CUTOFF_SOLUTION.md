# Hardware VCC Cutoff Solution (P0.13 on nice!nano boards)

**Date:** 2025-12-19  
**Discovery:** The nice!nano v2 (and some other boards) have a **built-in hardware VCC cutoff** circuit controlled by GPIO P0.13!

---

## What You Discovered

Your board documentation mentions:
> "External CVV cut-off control: When P0.13 is set to low, the power to the 3.3V-VCC pins will be turned off. This is useful for components that use less power when idle, such as RGB leds."

This is **EXACTLY** what you need for the trackball sensor power control!

---

## How It Works

### Hardware Circuit (Built into nice!nano v2)

The nice!nano v2 board has an **on-board load switch** controlled by P0.13:

```
          P0.13 GPIO
              ↓
        [Load Switch IC]
              ↓
          3.3V VCC pins (on board edge)
```

**When P0.13 = HIGH:** VCC pins powered (default)  
**When P0.13 = LOW:** VCC pins OFF (power saving mode)

This is a **hardware MOSFET/load switch** already on the board - no soldering needed!

---

## Checking If Your Board Has This Feature

### Option 1: Check Board Documentation

Look for:
- "VCC cutoff"
- "External power control"  
- "P0.13 power switch"
- "RGB power control"

### Option 2: Check Board Schematic

Look for:
- Load switch IC (TPS22860, AP2112, etc.) connected to P0.13
- MOSFET between 3.3V rail and VCC output pins
- P0.13 connected to enable pin

### Option 3: Check ZMK Board Definition

**File:** Check if your board's `.dts` file has:

```dts
EXT_POWER {
    compatible = "zmk,ext-power-generic";
    control-gpios = <&gpio0 13 GPIO_ACTIVE_HIGH>;
};
```

**Boards known to have this:**
- nice!nano v2 ✅
- ADV360 Pro ✅  
- CKP boards ✅
- (Check ZMK repo: `app/boards/arm/*/`)

---

## Implementation (If Your Board Has P0.13 Cutoff)

### Step 1: Connect Trackball to VCC Pin

**CRITICAL:** The trackball sensor VDD must be connected to the **VCC output pin** (the one controlled by P0.13), NOT directly to the 3.3V rail.

Check your wiring:
```
❌ WRONG: Trackball VDD → nRF52840 3.3V rail (bypasses cutoff)
✅ RIGHT: Trackball VDD → VCC output pin (controlled by P0.13)
```

On nice!nano v2, this is typically labeled as:
- "VCC" or "RAW" or "3.3V" pin on the Pro Micro pinout edge

### Step 2: Add EXT_POWER to Your Overlay

**File:** `boards/shields/keyball44/keyball44_right.overlay`

Add this node if not already present:

```dts
/ {
    EXT_POWER {
        compatible = "zmk,ext-power-generic";
        control-gpios = <&gpio0 13 GPIO_ACTIVE_HIGH>;
        init-delay-ms = <50>;
    };
};
```

### Step 3: Enable in Configuration

**File:** `config/keyball44_right.conf` (in your zmk-config repo)

```
CONFIG_ZMK_EXT_POWER=y
```

### Step 4: Control Power in Sleep/Wake

**Option A: Use Existing ZMK Behaviors**

ZMK already has `&ext_power` behaviors you can bind to keys:

```
&ext_power EP_ON   // Turn on VCC
&ext_power EP_OFF  // Turn off VCC
&ext_power EP_TOG  // Toggle VCC
```

You can add these to your keymap for manual control.

**Option B: Automatic Sleep/Wake Control**

The `ext_power_generic` driver already has PM hooks! When the device suspends:

```c
case PM_DEVICE_ACTION_SUSPEND:
    ext_power_generic_disable(dev);  // P0.13 → LOW → VCC OFF
    return 0;
    
case PM_DEVICE_ACTION_RESUME:
    ext_power_generic_enable(dev);   // P0.13 → HIGH → VCC ON
    return 0;
```

**This means it should AUTOMATICALLY cut VCC power during deep sleep!**

---

## Testing

### Phase 1: Verify Hardware Connection

1. **Power on keyboard**
2. **Measure voltage at trackball VDD pin**: Should be 3.3V
3. **Add to overlay:**
   ```dts
   EXT_POWER {
       compatible = "zmk,ext-power-generic";
       control-gpios = <&gpio0 13 GPIO_ACTIVE_LOW>;  // Test LOW = OFF
   };
   ```
4. **Flash and power on**
5. **Measure voltage at trackball VDD pin**: Should be 0V

**If VDD is still 3.3V:** Trackball is wired to wrong rail (not going through P0.13 switch)

### Phase 2: Test Manual Control

Add to your keymap:
```
&ext_power EP_OFF  // Bind to a key
```

1. **Press the key**
2. **Trackball should stop working** (powered off)
3. **Measure current**: Should drop significantly
4. **Press `&ext_power EP_ON` key**
5. **Trackball should work again**

### Phase 3: Test Automatic Sleep

1. **Build with CONFIG_ZMK_EXT_POWER=y**
2. **Flash firmware**
3. **Measure current in active mode**: ~1.95mA
4. **Wait for deep sleep** (15 minutes default)
5. **Measure current in sleep**: Should be **~0.20mA** ✅

---

## Expected Results

| State | P0.13 | VCC Output | Trackball | Current |
|-------|-------|------------|-----------|---------|
| Active | HIGH | 3.3V | Working | 1.95mA |
| Deep Sleep | LOW | 0V | Off | 0.20mA ✅ |
| Wake | HIGH | 3.3V | Working | 1.95mA |

**Battery Life:** ~115 days (5x improvement over 12 days!)

---

## Why This is Better Than External MOSFET

### Advantages

1. ✅ **No soldering required** (hardware already on board)
2. ✅ **No additional parts** ($0 cost)
3. ✅ **Software only solution** (just devicetree + config)
4. ✅ **Already integrated with ZMK** (ext_power driver)
5. ✅ **Proven design** (used for RGB LEDs on many keyboards)

### Requirements

1. ⚠️ **Board must have P0.13 VCC cutoff circuit**
2. ⚠️ **Trackball must be wired to controlled VCC pin**

---

## Troubleshooting

### Issue: Trackball never powers off

**Cause:** Trackball VDD is wired to wrong 3.3V source

**Fix:**
1. Check schematic - find which pin is controlled by P0.13
2. Rewire trackball VDD to that pin
3. Or use external MOSFET solution instead

### Issue: Current still high in sleep

**Cause:** EXT_POWER not being disabled during sleep

**Fix:**
1. Verify `CONFIG_ZMK_EXT_POWER=y` is set
2. Check devicetree has `EXT_POWER` node
3. Enable PM device logs:
   ```
   CONFIG_PM_DEVICE_LOG_LEVEL_DBG=y
   ```
4. Check logs for "ext_power" suspend messages

### Issue: Trackball doesn't work after wake

**Cause:** Power-on delay too short

**Fix:**
1. Increase `init-delay-ms`:
   ```dts
   init-delay-ms = <100>;  // Increase from 50ms
   ```
2. Sensor needs time to boot after power restored

---

## Comparison: Hardware Solutions

| Solution | Cost | Difficulty | Soldering | Result |
|----------|------|------------|-----------|--------|
| **P0.13 VCC Cutoff** | $0 | Easy | None* | 0.20mA ✅ |
| **External MOSFET** | $0.34 | Medium | Yes | 0.20mA ✅ |
| **Load Switch IC** | $0.40 | Medium | Yes | 0.20mA ✅ |

*May need to rewire if trackball connected to wrong VCC source

---

## Next Steps

### 1. Determine If Your Board Has This Feature

Check:
- Board documentation
- ZMK board definition files
- Schematic (if available)

### 2. If YES: Implement Software-Only Solution

- Add `EXT_POWER` node to overlay
- Enable `CONFIG_ZMK_EXT_POWER=y`
- Test with multimeter
- Verify 0.20mA sleep current

### 3. If NO: Use External MOSFET Solution

Follow [MOSFET_POWER_SWITCH_SOLUTION.md](./MOSFET_POWER_SWITCH_SOLUTION.md)

---

## Boards With P0.13 VCC Cutoff

Based on ZMK source code analysis:

| Board | Has P0.13 Cutoff | Notes |
|-------|------------------|-------|
| nice!nano v2 | ✅ Yes | Built-in load switch |
| nice!nano v1 | ❌ No | Earlier version |
| ADV360 Pro | ✅ Yes | Uses P0.13 control |
| CKP boards | ✅ Yes | Uses P0.13 control |
| nRFMicro | ❓ Unknown | Check schematic |
| Puchi-BLE | ❓ Unknown | Check schematic |

**Check your specific board!**

---

## Conclusion

If your board has the P0.13 VCC cutoff circuit:
- **You can solve the power issue with ZERO hardware modifications**
- Just devicetree + config changes
- Should achieve ~0.20mA deep sleep immediately

This is the **ideal solution** - hardware power switch already built-in, just needs to be enabled in software!

---

## References

- [ZMK ext_power_generic.c](https://github.com/zmkfirmware/zmk/blob/main/app/src/ext_power_generic.c)
- [nice!nano v2 DTS](https://github.com/zmkfirmware/zmk/blob/main/app/boards/arm/nice_nano/nice_nano_v2.dts)
- [ZMK External Power Config](https://zmk.dev/docs/config/power#external-power-control)
