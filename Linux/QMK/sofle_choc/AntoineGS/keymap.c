#include QMK_KEYBOARD_H
#include "keymap.h"
#include "features/socd_cleaner.h"

socd_cleaner_t socd_v = {{KC_W, KC_S}, SOCD_CLEANER_LAST};
socd_cleaner_t socd_h = {{KC_A, KC_D}, SOCD_CLEANER_LAST};

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {
    // clang-format off
    [DEF] = {LAYOUT(
        KC_1,     KC_2,   KC_3,    KC_4,    KC_5,    KC_6,                       XXXXXXX,     XXXXXXX,     XXXXXXX,    XXXXXXX,    XXXXXXX, XXXXXXX,
        KC_ESC,   KC_Q,   KC_W,    KC_E,    KC_R,    KC_T,                       XXXXXXX,     XXXXXXX,     XXXXXXX,    XXXXXXX,    XXXXXXX, XXXXXXX,
        KC_TAB,   KC_A,   KC_S,    KC_D,    KC_F,    KC_G,                       XXXXXXX,     XXXXXXX,     XXXXXXX,    XXXXXXX,    XXXXXXX, XXXXXXX,
        KC_LSFT,  KC_Z,   KC_X,    KC_C,    KC_V,    KC_B,      QK_BOOT, XXXXXXX,XXXXXXX,     XXXXXXX,     XXXXXXX,    XXXXXXX,    XXXXXXX, XXXXXXX,
                          KC_LCTL, KC_SPC,  KC_LALT, LA_MIRROR, KC_ENT,  XXXXXXX,XXXXXXX,     XXXXXXX,     XXXXXXX,    XXXXXXX
    )},
    [MIRROR] = {LAYOUT(
        KC_0,    KC_9,    KC_8,    KC_7,    KC_6,    KC_5,                       XXXXXXX,     XXXXXXX,     XXXXXXX,    XXXXXXX,    XXXXXXX, XXXXXXX,
        KC_BSPC, KC_P,    KC_O,    KC_I,    KC_U,    KC_Y,                       XXXXXXX,     XXXXXXX,     XXXXXXX,    XXXXXXX,    XXXXXXX, XXXXXXX,
        KC_QUOT, KC_SCLN, KC_L,    KC_K,    KC_J,    KC_H,                       XXXXXXX,     XXXXXXX,     XXXXXXX,    XXXXXXX,    XXXXXXX, XXXXXXX,
        KC_RSFT, KC_SLSH, KC_DOT,  KC_COMM, KC_M,    KC_N,      QK_BOOT, XXXXXXX,XXXXXXX,     XXXXXXX,     XXXXXXX,    XXXXXXX,    XXXXXXX, XXXXXXX,
                          KC_LCTL, KC_SPC,  KC_LALT, LA_MIRROR, KC_ENT,  XXXXXXX,XXXXXXX,     XXXXXXX,     XXXXXXX,    XXXXXXX
    )}
};

bool process_record_user(uint16_t keycode, keyrecord_t* record) {
  if (!process_socd_cleaner(keycode, record, &socd_v)) { return false; }
  if (!process_socd_cleaner(keycode, record, &socd_h)) { return false; }
  return true;
}

#if defined(ENCODER_MAP_ENABLE)
const uint16_t PROGMEM encoder_map[][NUM_ENCODERS][NUM_DIRECTIONS] = {
    [DEF] = { ENCODER_CCW_CW(KC_VOLD, KC_VOLU), ENCODER_CCW_CW(KC_MPRV, KC_MNXT) },
    [MIRROR] = { ENCODER_CCW_CW(KC_VOLD, KC_VOLU), ENCODER_CCW_CW(KC_MPRV, KC_MNXT) },
};
#endif
