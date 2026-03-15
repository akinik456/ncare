NCare Data Model

Root Collections

locators
requesters

---

locators/{locatorId}

Live device telemetry.

Fields:

name
lastSeen
battery
gpsEnabled
pairedRequesterId
pairedRequesterName

---

requesters/{requesterId}

Requester profile.

Fields may include:

name
createdAt

---

requesters/{requesterId}/locators/{locatorId}

Requester configuration for a locator.

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

Alert records.

Types:

call_me
battery_low
geofence_exit
gps_off (planned)

---

requesters/{requesterId}/requests/{requestId}

Location requests.

Locator responses stored under:

responses/{requestId} 
