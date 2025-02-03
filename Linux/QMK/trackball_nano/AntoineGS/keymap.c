/* Copyright 2021 Colin Lam (Ploopy Corporation)
 * Copyright 2020 Christopher Courtney, aka Drashna Jael're  (@drashna) <drashna@live.com>
 * Copyright 2019 Sunjun Kim
 * Copyright 2019 Hiroyuki Okada
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
#include QMK_KEYBOARD_H
#undef POINTING_DEVICE_ROTATION_270_RIGHT

// Dummy
const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {{{ KC_NO }}};
const int16_t ACCEL_DIVIDER = 8; // original is 16
int16_t PloopyNumlockScrollVDir = 1;
bool DoScroll = false;

void suspend_power_down_user(void) {
    // Switch off sensor + LED making trackball unable to wake host
    adns5050_power_down();
}

void suspend_wakeup_init_user(void) {
    adns5050_init();
}

report_mouse_t pointing_device_task_user(report_mouse_t mouse_report) {
    int x = mouse_report.x;
    int y = mouse_report.y;

    if (DoScroll) {
        // Scroll is very sensitive if you use the default values.
        // We can't divide it by anything to reduce the sensitivity, cause that would zero out small input values.
        // Instead we simply want either a 0, 1, or -1 depending on the input value's sign.
        x = (x > 0 ? 1 : (x < 0 ? -1 : 0));
        y = PloopyNumlockScrollVDir * (y > 0 ? 1 : (y < 0 ? -1 : 0));
        mouse_report.v = x;
        mouse_report.v = y;
        return mouse_report;
    }

    mouse_report.x = (x > 0 ? x*x/ACCEL_DIVIDER+x : -x*x/ACCEL_DIVIDER+x);
    mouse_report.y = (y > 0 ? y*y/ACCEL_DIVIDER+y : -y*y/ACCEL_DIVIDER+y);

    return mouse_report;
}

// https://docs.qmk.fm/features/pointing_device
bool process_record_user(uint16_t keycode, keyrecord_t *record) {
    DoScroll = host_keyboard_led_state().num_lock;
    return true;
}
