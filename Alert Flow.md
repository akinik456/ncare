NCare Alert Flow

NCare uses an event-driven alert architecture.

Alerts originate from three sources:

Locator device
Requester device
Server-side triggers

---

Call Request

Locator triggers a call request.

Flow:

Locator → Firestore alert record
Firestore trigger → FCM message
Requester device displays notification

---

Battery Alert

Locator periodically checks battery level.

If battery falls below configured threshold:

Locator → Firestore alert record
FCM → requester notification

---

Geofence Alert

Locator checks distance from configured location.

If locator leaves radius:

Locator → Firestore alert record
FCM → requester notification

---

GPS Disabled Alert (planned)

Locator detects GPS disabled state.

Locator → Firestore alert record
Requester notified to check device.

---

Notification Gateway

All notifications are routed through:

NotificationService

This ensures consistent handling in:

foreground
background
app killed state 
