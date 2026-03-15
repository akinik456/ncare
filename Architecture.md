NCare Architecture

NCare is a device presence and safety system designed for family use.

The architecture is intentionally simple and robust.

Core idea:

Locator devices continuously publish telemetry while requesters monitor device health and request location when needed.

---

System Components

Locator Device
Requester Device
Firebase Firestore
Firebase Cloud Messaging (FCM)

---

Locator Responsibilities

Locator periodically publishes telemetry:

- lastSeen
- battery level
- GPS enabled state

Locator responds to location requests and sends its coordinates.

Locator never pulls data from requester. It only responds to events.

---

Requester Responsibilities

Requester monitors locator health:

- ONLINE / OFFLINE
- battery level
- GPS state

Requester can:

- request location
- configure alerts
- manage paired locators

---

Data Flow

Locator → Firestore → Requester UI

Locator → Firestore → Cloud Function → FCM → Requester

Requester → Firestore request → FCM → Locator

---

Key Design Rules

Locator writes telemetry.
Requester reads telemetry.
Firestore acts as the event backbone.

Push notifications are used only for events, not for continuous data flow.

---

Reliability Strategy

Presence updates every 30 seconds.

ONLINE state defined as:

lastSeen < 120 seconds

System tolerates temporary connectivity loss.

---

Notification Strategy

Notifications are routed through a central notification gateway inside the app.

This ensures:

- consistent UI behavior
- easy future extension
- alert filtering

---

Scalability

Current version supports:

1 locator → 1 requester

Future versions may support many-to-many relationships. 
NCare Architecture

NCare is a device presence and safety system designed for family use.

The architecture is intentionally simple and robust.

Core idea:

Locator devices continuously publish telemetry while requesters monitor device health and request location when needed.

---

System Components

Locator Device
Requester Device
Firebase Firestore
Firebase Cloud Messaging (FCM)

---

Locator Responsibilities

Locator periodically publishes telemetry:

- lastSeen
- battery level
- GPS enabled state

Locator responds to location requests and sends its coordinates.

Locator never pulls data from requester. It only responds to events.

---

Requester Responsibilities

Requester monitors locator health:

- ONLINE / OFFLINE
- battery level
- GPS state

Requester can:

- request location
- configure alerts
- manage paired locators

---

Data Flow

Locator → Firestore → Requester UI

Locator → Firestore → Cloud Function → FCM → Requester

Requester → Firestore request → FCM → Locator

---

Key Design Rules

Locator writes telemetry.
Requester reads telemetry.
Firestore acts as the event backbone.

Push notifications are used only for events, not for continuous data flow.

---

Reliability Strategy

Presence updates every 30 seconds.

ONLINE state defined as:

lastSeen < 120 seconds

System tolerates temporary connectivity loss.

---

Notification Strategy

Notifications are routed through a central notification gateway inside the app.

This ensures:

- consistent UI behavior
- easy future extension
- alert filtering

---

Scalability

Current version supports:

1 locator → 1 requester

Future versions may support many-to-many relationships. 
