# NCare – DEV CONTEXT (Multi Requester Phase)

## 🎯 Project Status

NCare is a production-oriented mobile safety app.

### Current Capabilities

* Deterministic alerts:

  * GPS off
  * Battery low
  * Geofence exit
  * Multi-place (arrive / left)
* Request/Response system (RL flow)
* Pairing system with approval
* Firebase (Firestore + FCM)
* Safe location service abstraction (no direct Geolocator misuse)
* Notification pipeline:

  * Cloud Function → FCM → device → local notification

---

## 🧠 Core Architecture

### Entities

#### Locator

* Shares live location
* Sends alerts
* Responds to requests

#### Requester

* Sends location requests (RL)
* Receives alerts
* Configures settings

---

## 🔗 Firestore Structure (Current)

```
locators/{locatorId}
requesters/{requesterId}

requesters/{requesterId}/locators/{locatorId}
requesters/{requesterId}/locators/{locatorId}/responses/{requestId}
requesters/{requesterId}/locators/{locatorId}/places/{placeId}

requesters/{requesterId}/alerts/{alertId}
requesters/{requesterId}/requests/{requestId}
```

---

## 📍 Places System

* Max 3 places per locator
* Shared across all requesters
* Each place:

  * name
  * lat/lng
  * address
  * radiusMeters (fixed)
  * enabled
  * lastState (inside/outside)
  * lastTransitionAt

### Behavior

* Any requester can overwrite places
* Places are locator-based (not requester-based)
* Arrive / Left alerts generated per place
* Cooldown: 120 seconds

---

## 🔔 Alert System

### Types

* call_me
* gps_off
* battery_low
* geofence_exit
* place_arrive_<placeId>
* place_left_<placeId>

### Flow

1. Locator generates alert
2. Written to Firestore
3. Cloud Function (index.ts) triggers
4. FCM sent to requester(s)
5. Device shows local notification

---

## 🔐 Pairing System (Current – SINGLE REQUESTER)

```
locators/{locatorId}
  pairedRequesterId
  pairedRequesterName
```

* Pair request → approval → pairing
* Full validation:

  * Cloud (request send)
  * Locator (FG/BG receive)
  * Requester (response accept)

---

## 🚨 Security Model

Request is valid ONLY IF:

```
pairedRequesterId == requesterId
```

Validated in:

* Cloud Function (onRequestCreated)
* Locator (FG + BG message handler)
* Requester (response StreamBuilder gate)

---

## 🔄 NEXT PHASE: MULTI REQUESTER

### Target Model

```
locators/{locatorId}/paired_requesters/{requesterId}
```

---

## 🎯 Multi-Requester Rules

1. Each paired requester can send RL
2. Locator can send alerts to all paired requesters
3. Alerts filtered by requester’s own settings
4. Each requester has independent:

   * alert settings
   * request/response flow
5. Places are shared (max 3 per locator)
6. Any requester can modify places
7. Remove/unpair affects only that requester
8. Pairing approval is requester-specific

---

## ⚠️ Critical Refactor Points

Must update:

* pairedRequesterId → multi structure
* Cloud Function request gate
* Locator FG/BG request validation
* Requester response validation
* Remove/unpair logic
* Pairing approval logic

---

## 🧭 Development Rules

* Step-by-step ONLY
* No code unless explicitly requested
* Short and precise answers
* No unnecessary architecture changes
* Always preserve working features
* Safety and determinism first

---

## 🚀 Starting Task

Identify all places in code where:

* pairedRequesterId is used
* single requester assumption exists

DO NOT modify code yet.
Only map dependencies.

Wait for instruction before next step.
