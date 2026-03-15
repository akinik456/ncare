NCare – Dev Context

Purpose

NCare is a family safety & presence system where a requester (parent / caregiver) can check the status of a locator (child / elderly phone).
Core principle:

Pay once – use forever.
No subscriptions. Rock-solid reliability.

---

Architecture Overview

Roles

Locator

Device that sends:

- presence (online / lastSeen)
- battery level
- GPS status
- location when requested

Requester

Device that:

- monitors locator status
- requests location
- receives alerts
- manages settings

---

Firestore Structure

Root Collections

locators/{locatorId}

Live device telemetry.

Fields:

name
lastSeen
battery
gpsEnabled
pairedRequesterId
pairedRequesterName

Updated by locator every ~30 seconds.

---

requesters/{requesterId}

Requester profile.

---

requesters/{requesterId}/locators/{locatorId}

Requester-side configuration for a locator.

Fields:

name
active
callEnabled
batteryAlarmEnabled
batteryAlertThreshold
geofenceAlarmEnabled
geofenceRadius
createdAt

---

requesters/{requesterId}/alerts/{alertId}

Generated alerts.

Examples:

call_me
battery_low
geofence_exit
gps_off (planned)

---

requesters/{requesterId}/requests/{requestId}

Location requests.

Locator responds into:

requesters/{requesterId}/responses/{requestId}

---

Presence System

Locator periodically writes:

lastSeen
battery
gpsEnabled

This powers:

- ONLINE / LAST SEEN
- battery display
- GPS status

Requester calculates ONLINE if:

now - lastSeen < 120 seconds

---

Notification Gateway

All push notifications go through:

NotificationService

Used by:

- foreground messages
- background handler
- UI alerts

Notification types:

rl          (location request)
call_me
battery_low
geofence_exit

---

UI Status Panel (Requester)

Locator card shows:

ONLINE / Last seen
Battery level
GPS status
Distance to locator

Distance computed locally using:

Geolocator.distanceBetween()

Animated pulse indicator for ONLINE state.

---

Pairing Flow

1. Requester scans or enters locator ID
2. Requester configures alert settings
3. Firestore writes:

requesters/{requesterId}/locators/{locatorId}

4. Locator receives:

pairedRequesterId
pairedRequesterName

Locator can only have one requester (current design).

---

Alerts Implemented

Call Request

Locator asks requester to call.

Battery Alert

Triggered when battery below configured threshold.

Geofence (foundation ready)

Will trigger when locator leaves configured radius.

---

Device Telemetry

Locator periodically reports:

lastSeen
battery
gpsEnabled

Used for:

- online/offline detection
- battery monitoring
- GPS health

---

Current State (Stable)

Working:

✔ pairing
✔ location request system
✔ foreground/background messaging
✔ presence telemetry
✔ online/offline detection
✔ battery reporting
✔ GPS status reporting
✔ animated locator status UI
✔ distance calculation

---

Next Planned Features

1. Movement detection
2. GPS-off alert
3. Geofence engine
4. Locator health monitoring
5. Many-to-many pairing (future)
6. Settings refactor
7. Architecture cleanup

---

Design Principles

- Minimal UI
- Maximum reliability
- No background service abuse
- Foreground-safe Android behavior
- Firestore as event backbone
- Simple architecture over clever architecture

---

Motto

Pay once. Use forever. 
