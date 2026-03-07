# NCare - Development Context

## Project Overview

NCare is an Android-based family location request system.

The app allows a **requester device** to send a location request to a **locator device**.  
The locator automatically retrieves GPS location and writes the response.

Main goal:

A simple and reliable system for families to request the location of a child, elder, or relative.

Example use case:

Parent → requests location  
Child phone → automatically sends GPS location

---

# System Architecture

Current architecture uses:

Requester → Firestore → Cloud Function → FCM → Locator → GPS → Firestore response

Flow:

1. Requester creates request
2. Cloud Function sends push notification
3. Locator receives push
4. Foreground service starts
5. GPS retrieved
6. Response written to Firestore
7. Requester reads response

---

# Firestore Structure (Current)

## Requests
