#pragma once

// Enabling this option changes the startup behavior to listen for an
// active USB communication to delegate which part is master and which
// is slave. With this option enabled and theres’s USB communication,
// then that half assumes it is the master, otherwise it assumes it
// is the slave.
//
// I've found this helps with some ProMicros where the slave does not boot
#define SPLIT_USB_DETECT

#define RGB_MATRIX_SLEEP       // turn off effects when suspended
#define SPLIT_TRANSPORT_MIRROR // If LED_MATRIX_KEYPRESSES or
                               // LED_MATRIX_KEYRELEASES is enabled, you also
                               // will want to enable SPLIT_TRANSPORT_MIRROR
// limits maximum brightness of LEDs (max 255). Higher may cause the
// controller to crash.
#define RGB_MATRIX_MAXIMUM_BRIGHTNESS 100
