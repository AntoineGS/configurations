/*
 * Copyright (c) 2024 The ZMK Contributors
 *
 * SPDX-License-Identifier: MIT
 */

#define DT_DRV_COMPAT zmk_input_processor_accel

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <drivers/input_processor.h>

#include <zephyr/logging/log.h>

LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

struct accel_config {
    uint8_t type;
    int16_t accel_divider;
    size_t codes_len;
    uint16_t codes[];
};

// Quadratic acceleration formula from QMK: (x > 0 ? x*x/div+x : -x*x/div+x)
static int accel_val(struct input_event *event, int16_t divider) {
    int16_t x = event->value;

    if (x == 0) {
        return 0;
    }

    // Apply quadratic acceleration
    int16_t accel = (x > 0) ? (x * x / divider + x) : (-x * x / divider + x);

    LOG_DBG("accelerated %d with divider %d to %d", event->value, divider, accel);

    event->value = accel;
    return 0;
}

static int accel_handle_event(const struct device *dev, struct input_event *event,
                              uint32_t param1, uint32_t param2,
                              struct zmk_input_processor_state *state) {
    const struct accel_config *cfg = dev->config;

    if (event->type != cfg->type) {
        return ZMK_INPUT_PROC_CONTINUE;
    }

    // Check if this code should be accelerated
    for (int i = 0; i < cfg->codes_len; i++) {
        if (cfg->codes[i] == event->code) {
            return accel_val(event, cfg->accel_divider);
        }
    }

    return ZMK_INPUT_PROC_CONTINUE;
}

static struct zmk_input_processor_driver_api accel_driver_api = {
    .handle_event = accel_handle_event,
};

#define ACCEL_INST(n)                                                                              \
    static const struct accel_config accel_config_##n = {                                          \
        .type = DT_INST_PROP_OR(n, type, INPUT_EV_REL),                                            \
        .accel_divider = DT_INST_PROP_OR(n, accel_divider, 8),                                     \
        .codes_len = DT_INST_PROP_LEN(n, codes),                                                   \
        .codes = DT_INST_PROP(n, codes),                                                           \
    };                                                                                             \
    DEVICE_DT_INST_DEFINE(n, NULL, NULL, NULL, &accel_config_##n, POST_KERNEL,                     \
                          CONFIG_KERNEL_INIT_PRIORITY_DEFAULT, &accel_driver_api);

DT_INST_FOREACH_STATUS_OKAY(ACCEL_INST)
