// ============================================================
//  TFT_eSPI — User_Setup.h
//  LOLIN32 + SmartElex 2.8" ILI9341 240x320 SPI (non-touch)
//  JiffyTrails Navigator
//
//  Copy into <sketchbook>/libraries/TFT_eSPI/ replacing the
//  file that ships with the library, then RESTART the IDE.
// ============================================================

#define USER_SETUP_INFO "LOLIN32 ILI9341 2.8in"

// ---------- Driver ----------
//#define ILI9341_DRIVER
#define ILI9341_2_DRIVER   // alt init seq, TFT_eSPI issue 1172

// ---------- Pins ----------
// NOTE: TFT_RST is 16, not 4. GPIO4 is not broken out on the
// LOLIN32, and most ILI9341 tutorials say 4.
#define TFT_MISO 19
#define TFT_MOSI 23
#define TFT_SCLK 18
#define TFT_CS   15
#define TFT_DC    2
#define TFT_RST  16

// Backlight is tied to 3V3 in hardware for now. When auto-dim
// is added, move LED to a PWM pin and uncomment these.
// #define TFT_BL   17
// #define TFT_BACKLIGHT_ON HIGH

// ---------- Fonts ----------
// FONT8 is the 75px numeric face used for the distance readout.
#define LOAD_GLCD
#define LOAD_FONT2
#define LOAD_FONT4
#define LOAD_FONT6
#define LOAD_FONT7
#define LOAD_FONT8
#define LOAD_GFXFF
#define SMOOTH_FONT

// ---------- SPI ----------
// Reads are less tolerant than writes, hence the lower read clock.
#define SPI_FREQUENCY       27000000

/*
  Reads are MUCH slower than writes on this controller, and 20 MHz was too
  fast. MISO is wired, yet the boot probe in display.cpp kept coming back with
  garbage and disarming the panel watchdog - so the one mechanism that could
  recover the mirrored-screen fault was switched off by a number, not by a
  missing wire.

  6 MHz because reads happen twice every two seconds and their speed is worth
  nothing. If the boot line now says "watchdog armed", the watchdog is real and
  a corrupted MADCTL heals itself within six seconds instead of persisting
  until a power cycle.
*/
#define SPI_READ_FREQUENCY   6000000
