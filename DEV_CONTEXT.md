# NCare - DEV CONTEXT (V1 FINAL PHASE)

## CORE PRINCIPLES
- Deterministic system (no randomness in behavior)
- No architecture change unless critical
- Simple > clever
- Production-ready decisions only

---

## CURRENT FEATURES

### Identity
- Device can be:
  - Locator
  - Requester
- Identity stored locally (SharedPreferences)

---

### Pairing
- QR + 6 digit code
- Flow:
  requester → send request → locator approves → paired

- Data model:
  locators/{locatorId}/paired_requesters/{requesterId}

---

### Request / Response
- requester sends RL
- locator responds with location
- response stored per requestId

---

### Alerts
- gps_off
- battery_low
- call_me
- place_left / place_arrive

- Alerts stored under:
  requesters/{requesterId}/alerts/{alertId}

---

### Places
- max 3 per locator
- shared across requesters
- arrive / left alerts
- cooldown applied

---

## NEW DECISIONS (CRITICAL)

### ❗ NO DELETE POLICY
- request ❌ delete
- response ❌ delete
- alerts ❌ delete

→ retention based (24h planned)

---

### ❗ MULTI-DEVICE (FAKE MULTI-REQ)
- same requesterId can be used on multiple devices
- behavior:

#### Shared:
- alerts → all devices
- call_me → all devices
- settings → shared

#### Separated:
- request / response → device-based filtering (planned)

---

### ❗ ALERT SYSTEM CHANGE
OLD:
- alert → clear/delete

NEW:
- NO DELETE
- NO CLEAR

Behavior:
- events are written only on state change
- historical log preserved

---

### ❗ DATA MODEL

requesters/{requesterId}
  └── locators/{locatorId}
        └── responses/{requestId}

  └── alerts/{alertId}

locators/{locatorId}
  └── paired_requesters/{requesterId}

---

### ❗ MONETIZATION MODEL

- Product = Locator
- Each locator has:
  - max requester count

Example:
- 1 locator + 1 requester
- 1 locator + 2 requester (upgrade)

---

## NEXT STEPS

1. Remove all delete logic
2. Ensure no duplicate alert spam
3. Add requestSourceId (device separation)
4. Add retention cleanup (24h)
5. Stabilize lifecycle (bg/fg/restart)

---

## RULES

- Step by step only
- No unnecessary refactor
- No feature creep
- Test after every change

---

## STATUS

Core: ✅ Strong  
Multi-loc: ✅ Working  
Multi-req (shared): ✅ 90%  
Alerts: ⚠️ refactoring in progress
