# NCARE - DEV CONTEXT

## Project Goal
NCare is a lightweight emergency location request system.

Flow:

A → request location
↓
Firebase (Firestore trigger)
↓
Cloud Function
↓
FCM push
↓
B device receives push
↓
Native wake
↓
Foreground service
↓
Location fetch
↓
Send response

---

## Current Status

Working components:

✔ Firebase project created  
✔ Firestore database active  
✔ Cloud Function deployed (onRequestCreated)  
✔ Firestore trigger working  
✔ FCM push pipeline working  
✔ DeviceStateManager implemented  
✔ Location permission check implemented  
✔ GPS state check implemented  
✔ READY / NOT READY system working  
✔ Setup flow implemented  
✔ Setup flag persistence (shared_preferences)

---

## App Flow

App start:

setup_done ?
↓
false → SetupScreen
true → HomeScreen

SetupScreen:

Device ready state:
- Location permission
- Background location
- GPS enabled

When READY:
User can complete setup.

---

## Current UI

Setup Screen:
- DEVICE READY / NOT READY
- Permission check button
- Complete setup button

Home Screen:
- READY / NOT READY state
- Setup navigation button

---

## Core Classes

DeviceStateManager  
- permission check
- gps check
- ready stream

SetupManager  
- setup_done flag
- shared_preferences persistence

---

## Dependencies

permission_handler  
geolocator  
shared_preferences  
firebase_core  
firebase_messaging

---

## Next Step

Implement:

Firebase push → native handler

Native MessagingService:

Receive push
↓
Start foreground service
↓
Fetch location
↓
Send response to Firestore

---

## Long Term Plan

Add group mode:

A ↔ B ↔ C ↔ D

Multiple users share location requests.

---

## Repo

Local path:
C:\ncare