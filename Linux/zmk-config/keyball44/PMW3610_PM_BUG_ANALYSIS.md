# PMW3610 Power Management Bug Analysis

**Date:** 2025-12-19
**Issue:** PMW3610 trackball consuming 1.75mA in deep sleep instead of <10µA

---

## Investigation Summary

Through systematic power measurement testing, we identified:
- **Baseline (board + display):** 0.20mA (200µA) ✅
- **Display in deep sleep:** ~0µA (negligible) ✅
- **PMW3610 in deep sleep:** 1.75mA ❌ **(175x too high!)**

CONFIG_PMW3610_PM=y is enabled and the driver's suspend function IS being called, but the sensor is NOT entering low-power state.

---

## Root Cause: SPI Clock Disable After Shutdown

**Location:** `/home/antoinegs/gits/zmk/modules/drivers/zmk-pmw3610-driver/src/pmw3610.c`

### The Bug

The PM suspend code (line 1025) calls:
```c
err = reg_write(dev, PMW3610_REG_SHUTDOWN, PMW3610_SHUTDOWN_ENABLE);
```

The `reg_write()` function (lines 182-204) performs these steps:
1. **Enable SPI clock** (register 0x2F = 0x01)
2. **Write shutdown register** (register 0x3B = 0xE7) - sensor enters shutdown
3. **Disable SPI clock** (register 0x2F = 0x00) - **⚠️ PROBLEM!**

### Why This Causes High Power Consumption

After writing the shutdown register (step 2), the sensor immediately enters shutdown mode. Then the code attempts to disable the SPI clock (step 3), which causes one of these issues:

**Scenario A: Wake-up on SPI transaction**
- Shutdown command puts sensor to sleep
- SPI clock disable transaction wakes it back up
- Sensor stays awake, consuming 1.75mA

**Scenario B: SPI clock stays enabled**
- Shutdown command succeeds
- SPI clock disable fails (sensor already shutdown, can't respond)
- SPI clock remains enabled internally, consuming power

**Scenario C: Incomplete shutdown**
- The rapid sequence prevents proper shutdown
- Sensor enters partial low-power state (REST1/REST2) instead of full shutdown
- Consumes more power than expected

---

## Evidence

1. ✅ **CONFIG_PMW3610_PM=y** is enabled in build config
2. ✅ **Suspend function IS called** - logs from Test 2 showed "Entering deep sleep"
3. ✅ **Shutdown register value is correct** - 0xE7 to register 0x3B (per PMW3610 datasheet)
4. ❌ **Power consumption is 1.75mA** - should be <10µA in shutdown mode
5. ❌ **SPI clock disable happens AFTER shutdown** - timing issue

---

## The Fix

### Option 1: Use `_reg_write()` directly for shutdown (RECOMMENDED)

Modify `pmw3610_pm_action()` at line 1020-1029:

**Current code:**
```c
case PM_DEVICE_ACTION_SUSPEND:
    LOG_INF("Entering deep sleep");
    // Disable interrupts before shutdown
    set_interrupt(dev, false);
    // Write shutdown enable command to shutdown register
    err = reg_write(dev, PMW3610_REG_SHUTDOWN, PMW3610_SHUTDOWN_ENABLE);
    if (err) {
        LOG_ERR("Failed to enter shutdown mode: %d", err);
    }
    break;
```

**Fixed code:**
```c
case PM_DEVICE_ACTION_SUSPEND:
    LOG_INF("Entering deep sleep");
    // Disable interrupts before shutdown
    set_interrupt(dev, false);

    // Enable SPI clock before shutdown
    err = _reg_write(dev, PMW3610_REG_SPI_CLK_ON_REQ, PMW3610_SPI_CLOCK_CMD_ENABLE);
    if (err) {
        LOG_ERR("Failed to enable SPI clock: %d", err);
        break;
    }

    // Write shutdown command - sensor will enter shutdown immediately
    // Do NOT disable SPI clock after this, as it may wake the sensor
    err = _reg_write(dev, PMW3610_REG_SHUTDOWN, PMW3610_SHUTDOWN_ENABLE);
    if (err) {
        LOG_ERR("Failed to enter shutdown mode: %d", err);
    }
    // Note: SPI clock left enabled in sensor, but sensor is in shutdown so it doesn't matter
    break;
```

### Option 2: Add delay before SPI clock disable

Add a delay between shutdown and SPI clock disable to ensure sensor has time to process shutdown:

```c
err = _reg_write(dev, PMW3610_REG_SHUTDOWN, PMW3610_SHUTDOWN_ENABLE);
if (err) {
    LOG_ERR("Failed to enter shutdown mode: %d", err);
    break;
}
// Wait for sensor to process shutdown before trying to disable SPI clock
k_msleep(10);
// Now try to disable SPI clock (may or may not work if sensor is already shutdown)
err = _reg_write(dev, PMW3610_REG_SPI_CLK_ON_REQ, PMW3610_SPI_CLOCK_CMD_DISABLE);
```

### Option 3: Skip SPI clock manipulation entirely for shutdown

The sensor's internal SPI clock state doesn't matter if it's in shutdown mode:

```c
case PM_DEVICE_ACTION_SUSPEND:
    LOG_INF("Entering deep sleep");
    set_interrupt(dev, false);
    // Use _reg_write directly without SPI clock enable/disable dance
    err = _reg_write(dev, PMW3610_REG_SHUTDOWN, PMW3610_SHUTDOWN_ENABLE);
    if (err) {
        LOG_ERR("Failed to enter shutdown mode: %d", err);
    }
    break;
```

---

## Testing the Fix

After implementing Option 1 (recommended):

1. Build and flash firmware
2. Wait 15 seconds for deep sleep
3. Measure current with precision tool
4. **Expected result:** ~0.20mA (just board baseline, no trackball consumption)
5. **If successful:** Total power reduced from 1.95mA to 0.20mA ✅

---

## Additional Considerations

### If fix doesn't work:

**Check for hardware issues:**
- Clone PMW3610 might not fully implement shutdown mode
- IRQ line pull-up (GPIO1.11) might need to be disabled during suspend
- SPI bus hardware might be drawing current

**Alternative workarounds:**
1. **Disable trackball during sleep** - Cut power via EXT_POWER GPIO
2. **Use REST2/REST3 modes** - Configure sensor to use deeper REST states
3. **Accept the drain** - 550mAh ÷ 1.95mA = ~12 days battery life

### Register Definitions (for reference):

From `pmw3610.h`:
- `PMW3610_REG_SHUTDOWN = 0x3B`
- `PMW3610_SHUTDOWN_ENABLE = 0xE7`
- `PMW3610_REG_SPI_CLK_ON_REQ = 0x2F`
- `PMW3610_SPI_CLOCK_CMD_ENABLE = 0x01`
- `PMW3610_SPI_CLOCK_CMD_DISABLE = 0x00`

---

## Next Steps

1. Implement Option 1 fix in pmw3610.c
2. Rebuild and flash firmware
3. Measure power consumption
4. If successful, contribute fix upstream to zmk-pmw3610-driver repository
5. Document final configuration for reference

---

## Files to Modify

- **Driver source:** `~/gits/zmk/modules/drivers/zmk-pmw3610-driver/src/pmw3610.c`
- **Lines to change:** 1020-1029 (PM_DEVICE_ACTION_SUSPEND case)
- **Testing:** Use `./build_flash.sh right` after changes
