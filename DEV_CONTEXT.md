# NCare – DEV CONTEXT

## Project Overview
NCare is a mobile app designed for **on-demand location requests** between two devices.

Primary scenario:
- Parent requests location
- Child / elderly phone sends location automatically

The **locator device does nothing manually**.  
Location is sent automatically when a request arrives.

---

# Architecture

## Request Flow

Requester device:
1. User taps **Request location**
2. App writes request to Firestore
3. Cloud Function triggers
4. FCM push sent to locator device

Locator device:
1. Receives FCM data message
2. Native FirebaseMessagingService catches message
3. Starts Foreground Service
4. Foreground Service requests GPS
5. Location sent to Firestore

Requester device:
1. Watches Firestore response
2. Displays location + address

---

# Firebase Structure

## requests
