/*
  ble.cpp — NimBLE peripheral. Phone is central and writes packets at ~1 Hz.

  Built against NimBLE-Arduino 2.5.1. The 2.x callback signatures take a
  NimBLEConnInfo& and onDisconnect takes a reason code; 1.x examples found
  online will not compile here.

  Everything that arrives on the write characteristic comes from an Android
  app that reverse-engineers Google Maps' navigation notification. That format
  is undocumented and has broken roughly annually, so this parser treats every
  incoming byte as hostile: it validates before it reads, and it stages a
  packet in locals and commits only once the whole packet has parsed. A
  half-applied packet would leave a real maneuver next to a stale distance,
  which is worse than showing nothing.
*/

#include <NimBLEDevice.h>

#include "ble.h"
#include "nav_types.h"
#include "watchdog.h"

// Serial diagnostics for the failure that actually happens in the field: the
// phone-side format shifts and packets start getting rejected. Compile out
// with -DBLE_TRACE=0 once the link is trusted.
#ifndef BLE_TRACE
#define BLE_TRACE 1
#endif
#if BLE_TRACE
#define BLE_LOG(...) Serial.printf(__VA_ARGS__)
#else
#define BLE_LOG(...) do {} while (0)
#endif

// ------------------------------------------------------------------ UUIDs

static const char* SVC_UUID    = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
static const char* CHR_WRITE   = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";  // phone -> ESP32
static const char* CHR_NOTIFY  = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";  // ESP32 -> phone

// 185 keeps the longest instruction seen in the wild (59 chars) inside a
// single write, so a packet is never split across ATT operations.
static const uint16_t PREFERRED_MTU = 185;

// [type:u8][len:u8] precedes every payload.
static const size_t FRAME_HEADER = 2;

// Advertising is restarted from bleTick(), not from the disconnect callback —
// calling into the GAP API from inside a NimBLE host callback is a known
// source of trouble. This is how long to wait before retrying a start() that
// the stack refused, e.g. because the disconnect had not fully settled.
static const uint32_t ADV_RETRY_MS = 500;

// ------------------------------------------------------------ module state

static NavState*            g_state     = nullptr;
static NimBLEServer*        g_server    = nullptr;
static NimBLECharacteristic* g_notifyChr = nullptr;
static volatile bool        g_connected = false;
static uint32_t             g_lastAdvMs = 0;

// ----------------------------------------------------------- byte reader

/*
  Bounds-checked cursor over a payload. Every read that would run past the
  end returns zero and latches ok() false, so a handler can read its whole
  fixed block and test validity once instead of guarding every field.

  Named PacketReader rather than Reader because this whole block is at file
  scope: xtensa gcc 14 ICEs when a namespace-scope function-pointer type
  names a class from an anonymous namespace (segfault on the PacketHandler
  table below), so the internal-linkage trick is not available here.
*/
class PacketReader {
 public:
  PacketReader(const uint8_t* p, size_t n) : m_p(p), m_n(n) {}

  uint8_t u8() {
    if (!take(1)) return 0;
    return m_p[m_i - 1];
  }

  uint16_t u16() {   // little-endian, per docs/BLE_PROTOCOL.md
    if (!take(2)) return 0;
    return static_cast<uint16_t>(m_p[m_i - 2]) |
           static_cast<uint16_t>(m_p[m_i - 1]) << 8;
  }

  uint32_t u32() {
    if (!take(4)) return 0;
    return static_cast<uint32_t>(m_p[m_i - 4])       |
           static_cast<uint32_t>(m_p[m_i - 3]) << 8  |
           static_cast<uint32_t>(m_p[m_i - 2]) << 16 |
           static_cast<uint32_t>(m_p[m_i - 1]) << 24;
  }

  bool           ok()        const { return m_ok; }
  const uint8_t* cursor()    const { return m_p + m_i; }
  size_t         remaining() const { return m_ok ? m_n - m_i : 0; }

 private:
  bool take(size_t n) {
    if (!m_ok || n > m_n - m_i) { m_ok = false; return false; }
    m_i += n;
    return true;
  }

  const uint8_t* m_p;
  size_t         m_n;
  size_t         m_i = 0;
  bool           m_ok = true;
};

// ------------------------------------------------------------- utf-8 tail

// Length of the longest prefix of `n` bytes that ends on a complete UTF-8
// code point. Truncating mid-sequence leaves a dangling lead byte that the
// font renderer draws as garbage, and road names in Bengaluru carry Kannada.
static size_t utf8Fit(const char* buf, size_t n) {
  size_t k = n;
  while (k > 0 && (static_cast<uint8_t>(buf[k - 1]) & 0xC0) == 0x80) k--;
  if (k == 0) return 0;   // nothing but continuation bytes: not text

  const uint8_t lead = static_cast<uint8_t>(buf[k - 1]);
  size_t need = 1;
  if      ((lead & 0xE0) == 0xC0) need = 2;
  else if ((lead & 0xF0) == 0xE0) need = 3;
  else if ((lead & 0xF8) == 0xF0) need = 4;

  return (k - 1 + need <= n) ? n : k - 1;
}

// Copies the trailing utf8 field into a fixed buffer. The wire format does
// not null-terminate, but a phone that appends one must not put a NUL in the
// middle of the displayed string, so the first NUL ends the field.
static void copyText(char* dst, size_t cap, const uint8_t* src, size_t n) {
  size_t len = n;
  for (size_t i = 0; i < len; i++) {
    if (src[i] == 0) { len = i; break; }
  }
  if (len > cap - 1) len = cap - 1;
  memcpy(dst, src, len);
  dst[utf8Fit(dst, len)] = '\0';
}

// ------------------------------------------------------------- handlers

// Each handler reads its payload, and applies nothing unless the whole thing
// parsed. Returning false drops the packet without touching NavState and
// without counting an arrival.

static bool handleNav(PacketReader& r, NavState& s) {
  const uint8_t  maneuver       = r.u8();
  const uint16_t dist_m         = r.u16();
  const uint8_t  next_maneuver  = r.u8();
  const uint16_t next_dist_m    = r.u16();
  const uint16_t eta_min        = r.u16();
  const uint16_t remaining_100m = r.u16();
  const uint8_t  flags          = r.u8();
  if (!r.ok()) return false;   // 11-byte fixed block was short

  // Staged first: a truncating copy must not be able to fail halfway and
  // leave the old road name beside the new arrow.
  char instruction[INSTRUCTION_MAX] = {0};
  copyText(instruction, sizeof(instruction), r.cursor(), r.remaining());

  s.maneuver       = maneuver;
  s.dist_m         = dist_m;
  s.next_maneuver  = next_maneuver;
  s.next_dist_m    = next_dist_m;
  s.eta_min        = eta_min;
  s.remaining_100m = remaining_100m;
  s.flags          = flags;
  memcpy(s.instruction, instruction, sizeof(s.instruction));
  return true;
}

static bool handleStatus(PacketReader& r, NavState& s) {
  const uint8_t flags = r.u8();
  const uint8_t pct   = r.u8();
  if (!r.ok()) return false;

  (void)flags;   // STATUS flags have no documented bits yet and no NavState
                 // field; deliberately not folded into s.flags, which is the
                 // NAV flag word.

  // A percentage outside 0-100 is a parser bug on the phone, not a reason to
  // drop an otherwise valid packet — clamp so the battery glyph stays sane.
  s.phoneBatteryPct = (pct > 100) ? 100 : pct;
  return true;
}

// Adding CALL/MEDIA/TRIP/CONFIG/TRAFFIC is a handler plus a row here. Until
// then those types fall through to the unknown-type path below, which still
// counts the arrival so the watchdog sees a live link.
struct PacketHandler {
  uint8_t type;
  bool (*apply)(PacketReader&, NavState&);
};

// An incoming call is persistent state — it stays on screen while ringing —
// so unlike a notification it carries no timestamp and is cleared by the phone
// sending CALL_IDLE. If the phone dies mid-ring the link drops, and
// DISCONNECTED outranks the band anyway.
static bool handleCall(PacketReader& r, NavState& s) {
  const uint8_t state = r.u8();
  if (!r.ok()) return false;
  if (state > CALL_ACTIVE) return false;   // undefined state, drop it

  char name[ALERT_TEXT_MAX] = {0};
  copyText(name, sizeof(name), r.cursor(), r.remaining());

  s.callState = state;
  memcpy(s.callName, name, sizeof(s.callName));
  return true;
}

// [u8 kind][u8 src_len][src bytes][text bytes to end].
//
// Length-prefixed rather than NUL-separated on purpose: PKT_MEDIA's
// "title \0 artist" is the one place in this protocol that splits on NUL, and
// a generic trailing-text reader silently eats the second field. A length
// prefix cannot be misread that way.
static bool handleNotify(PacketReader& r, NavState& s) {
  const uint8_t kind   = r.u8();
  const uint8_t srcLen = r.u8();
  if (!r.ok()) return false;
  if (srcLen > r.remaining()) return false;   // claims more source than arrived

  char src[ALERT_SRC_MAX] = {0};
  copyText(src, sizeof(src), r.cursor(), srcLen);

  PacketReader body(r.cursor() + srcLen, r.remaining() - srcLen);
  char text[ALERT_TEXT_MAX] = {0};
  copyText(text, sizeof(text), body.cursor(), body.remaining());

  if (text[0] == '\0') return false;   // nothing to show; not worth a redraw

  s.notifyKind = (kind > NOTIFY_ALERT) ? NOTIFY_GENERIC : kind;
  memcpy(s.notifySrc,  src,  sizeof(s.notifySrc));
  memcpy(s.notifyText, text, sizeof(s.notifyText));
  s.notifyAtMs = millis();
  return true;
}

static const PacketHandler HANDLERS[] = {
  { PKT_NAV,    handleNav    },
  { PKT_STATUS, handleStatus },
  { PKT_CALL,   handleCall   },
  { PKT_NOTIFY, handleNotify },
};
static const size_t N_HANDLERS = sizeof(HANDLERS) / sizeof(HANDLERS[0]);

// ---------------------------------------------------------------- framing

static void handleFrame(const uint8_t* frame, size_t n) {
  if (g_state == nullptr) return;

  if (n < FRAME_HEADER) {
    BLE_LOG("[ble] runt frame, %u bytes\n", (unsigned)n);
    return;
  }

  const uint8_t type  = frame[0];
  const uint8_t len   = frame[1];
  const size_t  avail = n - FRAME_HEADER;

  // `len` is advisory. The only length the radio actually guarantees is the
  // ATT write length, so that is what every read is bounded by. A len larger
  // than what arrived means a truncated or corrupt write and the frame is
  // dropped; a smaller one is tolerated because the phone side has miscounted
  // before — BUILD_PLAN.md's own worked example sends len=0x0F for a 24-byte
  // NAV payload and still expects the full road name to appear.
  if (len > avail) {
    BLE_LOG("[ble] type 0x%02X claims %u bytes, %u arrived\n",
            type, (unsigned)len, (unsigned)avail);
    return;
  }

  PacketReader r(frame + FRAME_HEADER, avail);

  for (size_t i = 0; i < N_HANDLERS; i++) {
    if (HANDLERS[i].type != type) continue;
    if (!HANDLERS[i].apply(r, *g_state)) {
      BLE_LOG("[ble] type 0x%02X malformed, %u bytes, dropped\n",
              type, (unsigned)avail);
      return;
    }
    watchdogNotePacket(*g_state);
    return;
  }

  // Unknown type: the payload means nothing to us yet, but the link is
  // demonstrably alive and freshness is measured in arrivals, not in NAV
  // packets (nav_types.h: 64 s of unchanging values were measured in traffic).
  watchdogNotePacket(*g_state);
}

// -------------------------------------------------------------- callbacks

namespace {

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo) override {
    g_connected = true;
    // NavState.linkUp is deliberately NOT written here. watchdogTick() is its
    // single writer, deriving it from bleConnected() once per loop, because it
    // needs the not-connected -> connected edge to restart the freshness clock.
    // Setting it from this callback would consume that edge and the branch
    // would never fire.

    // 15-30 ms interval, 1.8 s supervision timeout. The phone posts at ~1 Hz,
    // so a tighter interval only burns battery; the timeout is what decides
    // how fast a dead link becomes a visible disconnect.
    pServer->updateConnParams(connInfo.getConnHandle(), 12, 24, 0, 180);
    BLE_LOG("[ble] connected, mtu %u\n", connInfo.getMTU());
  }

  void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason) override {
    (void)pServer; (void)connInfo;
    g_connected = false;   // watchdogTick owns NavState.linkUp
    // Advertising is restarted by bleTick(), not here — see ADV_RETRY_MS.
    BLE_LOG("[ble] disconnected, reason %d\n", reason);
  }

  void onMTUChange(uint16_t mtu, NimBLEConnInfo& connInfo) override {
    (void)connInfo;
    BLE_LOG("[ble] mtu now %u\n", mtu);
  }
};

class WriteCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* pChr, NimBLEConnInfo& connInfo) override {
    (void)connInfo;
    const NimBLEAttValue v = pChr->getValue();
    handleFrame(v.data(), v.length());
  }
};

ServerCallbacks g_serverCallbacks;
WriteCallbacks  g_writeCallbacks;

}  // namespace

// ------------------------------------------------------------------- api

void bleBegin(NavState* state, const char* deviceName) {
  g_state = state;

  NimBLEDevice::init(deviceName != nullptr ? deviceName : "JiffyTrails");

  // Must follow init(): this sets the host's preferred MTU for the exchange
  // the central starts on connect.
  NimBLEDevice::setMTU(PREFERRED_MTU);

  g_server = NimBLEDevice::createServer();
  g_server->setCallbacks(&g_serverCallbacks, false);

  // The library can restart advertising itself on disconnect; turned off so
  // there is exactly one place that owns it, and it is outside the callback.
  g_server->advertiseOnDisconnect(false);

  NimBLEService* svc = g_server->createService(SVC_UUID);

  // WRITE_NR as well as WRITE: at 1 Hz the phone gains nothing from waiting
  // for a response, and a write-without-response cannot stall its own loop.
  svc->createCharacteristic(CHR_WRITE, NIMBLE_PROPERTY::WRITE |
                                       NIMBLE_PROPERTY::WRITE_NR)
     ->setCallbacks(&g_writeCallbacks);

  g_notifyChr = svc->createCharacteristic(CHR_NOTIFY, NIMBLE_PROPERTY::NOTIFY);

  svc->start();

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->setName(deviceName != nullptr ? deviceName : "JiffyTrails");
  adv->addServiceUUID(SVC_UUID);
  // A 128-bit UUID leaves no room for the name in the 31-byte advertisement,
  // so the name goes in the scan response or nRF Connect shows "N/A".
  adv->enableScanResponse(true);
  adv->start();

  g_lastAdvMs = millis();
}

void bleTick() {
  if (g_server == nullptr) return;
  if (g_connected) return;

  // Self-healing rather than disconnect-triggered: this also covers the case
  // where advertising stopped for a reason nothing told us about, which is
  // the whole point — the display has to come back without touching either
  // end of the link.
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  if (adv->isAdvertising()) return;

  const uint32_t now = millis();
  if (now - g_lastAdvMs < ADV_RETRY_MS) return;
  g_lastAdvMs = now;

  if (adv->start()) {
    BLE_LOG("[ble] advertising restarted\n");
  }
}

bool bleConnected() {
  return g_connected;
}

bool bleNotify(const uint8_t* data, size_t len) {
  if (!g_connected || g_notifyChr == nullptr) return false;
  if (data == nullptr || len == 0) return false;
  return g_notifyChr->notify(data, len);
}
