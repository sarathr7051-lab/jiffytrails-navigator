/*
  ble.h — NimBLE peripheral. Phone is central and writes packets at ~1 Hz.
  UUIDs and framing in docs/BLE_PROTOCOL.md.
*/
#pragma once
#include "nav_types.h"

// Brings up NimBLE, registers the service and starts advertising.
// `state` is stored and mutated in place as packets arrive.
void bleBegin(NavState* state, const char* deviceName);

// Call every loop. Handles re-advertising after a disconnect.
void bleTick();

// True while a central is connected.
bool bleConnected();

// Notify the phone (ESP32 -> phone characteristic). Used for the keep-alive
// nudge: if nothing has arrived for a while, prompt rather than wait.
bool bleNotify(const uint8_t* data, size_t len);
