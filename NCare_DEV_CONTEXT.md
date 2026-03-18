# NCare Dev Context

_Last updated: 2026-03-18T10:00:52.273605_

---

## 1. Project Overview
NCare is a real-time locator-requester system focused on peace of mind:
"Find them. Before you worry."

---

## 2. Architecture
- FCM = trigger
- Firestore = source of truth

---

## 3. Data Model

### Root
- locators/{locatorId}
- requesters/{requesterId}

### Locator
- name, lastSeen, lat, lng, acc, battery, gpsEnabled

### Requester
requesters/{requesterId}/locators/{locatorId}

- settings (battery, gps, geofence)

---

## 4. Alerts

State (deterministic):
- gps_off_{locatorId}
- battery_low_{locatorId}
- geofence_exit_{locatorId}

Event:
- call_me

---

## 5. Responses
requesters/{requesterId}/locators/{locatorId}/responses/{requestId}

---

## 6. Location Rule
Use only:
LocationService.getCurrentLocationSafe()

---

## 7. Pairing V1
- QR + Code
- Code = 6 char A-Z + 0-9

---

## 8. Principles
- State overwrite
- Event append
- No duplicates
- Firestore truth

---

## END
