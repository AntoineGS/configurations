#define SMTD_GLOBAL_TAP_TERM 500
#define LA_SYM MO(SYM)
#define LA_NAV MO(NAV)
#define LA_NUM MO(NUM)
#define MAX_DEFERRED_EXECUTORS 10

enum custom_keycodes {
    C_CIRC = SAFE_RANGE,
    C_QUOT, // '
    C_DGRV, // `
    C_DTIL, // ~
    C_AGRV, // À
    C_UGRV, // Ù
    C_UCIR, // Û
    C_OCIR, // Ô
    SW_WIN, // Switch to next window         (cmd-tab)
    SMTD_KEYCODES_BEGIN,
    C_A, // reads as C(ustom) + KC_A, but you may give any name here
    C_S,
    C_D,
    C_F,
    C_J,
    C_K,
    C_L,
    C_SCLN,
    C_EAIG, // É
    C_ECIR, // Ê
    C_EGRV, // È
    C_ETRE, // Ë
    C_LCBR, // {
    C_LBRC, // [
    C_LPRN, // (
    C_RPRN, // )
    C_RBRC, // ]
    C_RCBR, // }
    C_1,
    C_2,
    C_3,
    C_4,
    C_7,
    C_8,
    C_9,
    C_0,
    SMTD_KEYCODES_END,
};

// requires the SMTD* enums to be defined to needs to be after
#include "sm_td.h"

enum layers {
    DEF,
    SYM,
    NAV,
    NUM,
};

