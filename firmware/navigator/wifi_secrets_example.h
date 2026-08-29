/*
  Copy this file to wifi_secrets.h and fill it in. wifi_secrets.h is NOT
  tracked by git, so your credentials stay on this machine.

  With no wifi_secrets.h, or with an empty SSID, the firmware compiles exactly
  as before and OTA simply never starts.

  This is a home network, not the phone hotspot: OTA is for updating at the
  desk. On the road the join fails in six seconds and the radio switches off.
*/
#pragma once

// Your PHONE HOTSPOT, not a home network - see ota.h. Settings > Mobile
// Hotspot on the S24+. Keep the band on 2.4 GHz: the ESP32 has no 5 GHz radio.
#define WIFI_SSID ""
#define WIFI_PASS ""
