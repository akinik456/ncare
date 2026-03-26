Project Overview
NCare is a lightweight real-time safety and tracking platform.
Architecture supports many-to-many requester ↔ locator relationships with group-based routing.
Core principle:
minimal data
event-driven
no continuous heavy tracking
rock-solid background behavior
Roles
Locator
Device that shares location and sends alerts.
Requester
Device that requests location and receives alerts.
Data Model
Groups

groups/{groupId}
Devices

groups/{groupId}/devices/{deviceId}
Fields:

deviceId
role: requester | locator
name
active
joinedAt
Requests

groups/{groupId}/locators/{locatorId}/requests/{requestId}
Fields:

requesterId
requestDeviceId
ts
Responses

groups/{groupId}/locators/{locatorId}/responses/{responseId}
Fields:

requesterId
requestDeviceId
lat
lng
acc
ts
Alerts

groups/{groupId}/locators/{locatorId}/alerts/{alertId}
Fields:

type
locatorId
locatorName
requesterDeviceId (optional)
ts
extra...
Alert types:

call_me
gps_off
battery_low
place_arrive_x
place_left_x
Pairing Model
Locator root document:

locators/{locatorId}
Fields:

groupId
pairedRequesters: Map
pairedRequestersCount
pairedRequesters example:

pairedRequesters: {
   requesterId : {
      requesterId
      name
      joinedAt
      active
   }
}
Notification Flow
Firestore Alert Created ↓ Cloud Function (index.ts) ↓ FCM data message ↓ showFromRemoteMessage(RemoteMessage) ↓ Local notification
IMPORTANT: Server sends raw ts Client formats local timezone
showFromRemoteMessage Rules
Use only:

final data = message.data;
Do NOT read Firestore.
Timestamp:

final tsStr = data['ts'];
Format on device.
Call Me Logic
Modes:
single requester
broadcast (everybody)
Routing:

requesterDeviceId optional
If exists → send only to that device
If empty → send to all requester devices
UI Rules
Requester:
show only paired locators
request button disabled if none selected
Locator:
show all paired requester names
multi pairing supported
Background Behavior
Must work:
screen off
app killed
boot completed
doze mode
Foreground service required for locator.
Notification Requirements
timestamp displayed
dismiss removes banner
background notification same content
timezone local
Business Direction (Future)
Two app model planned:
Locator App (free)
tracking sender
emergency 112
utility features
Requester App (paid)
multi vehicle tracking
small business use
lifetime license
Stability Priority
No new features until:
pairing stable
multi requester stable
alert routing stable
background stable
Current Status
Core architecture complete:
many-to-many pairing ✔
group routing ✔
device-level alerts ✔
call_me individual ✔
timestamp sync ✔
notification sync ✔
System ready for polishing and V1 release.
