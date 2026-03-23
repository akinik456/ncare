import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

admin.initializeApp();

export const onRequestCreated = onDocumentCreated(
  {
    document: "groups/{groupId}/locators/{locatorId}/requests/{requestId}",
    region: "us-central1",
  },
  async (event) => {
    const groupId = event.params.groupId;
    const locatorId = event.params.locatorId;
    const requestId = event.params.requestId;
    const data = event.data?.data();

    const requesterId = data?.requesterId?.toString() ?? "";
    const requestDeviceId = data?.requestDeviceId?.toString() ?? "";

    if (!locatorId || !requestId || !requesterId) {
      console.log("INVALID REQUEST DATA", groupId, locatorId, requestId, requesterId);
      return;
    }

    const locatorTopic = `locator_${locatorId}`;

    const requesterDoc = await admin.firestore()
      .collection("requesters")
      .doc(requesterId)
      .get();

    const requesterName =
      requesterDoc.data()?.name?.toString() || "Requester";

    console.log(
      "REQUEST TRIGGERED",
      groupId,
      requesterId,
      requestId,
      locatorId,
      locatorTopic,
    );

    await admin.messaging().send({
      topic: locatorTopic,
      data: {
        type: "rl",
        groupId,
        requestId,
        requesterId,
        requestDeviceId,
        locatorId,
        requesterName,
      },
      android: { priority: "high" },
    });
  },
);

export const onAlertCreated = onDocumentCreated(
  {
    document: "requesters/{requesterId}/alerts/{alertId}",
    region: "us-central1",
  },
  async (event) => {
    const requesterId = event.params.requesterId;
    const alertId = event.params.alertId;
    const data = event.data?.data();

    const type = data?.type?.toString();
    const locatorId = data?.locatorId?.toString() ?? "";
    const locatorName = data?.locatorName?.toString() ?? "Locator";
    const level = data?.level?.toString() ?? data?.battery?.toString() ?? "";

    let title = "";
    let body = "";

    if (type === "call_me") {
      title = "Call request";
      body = `${locatorName} wants you to call`;
    } else if (type === "gps_off") {
      title = "GPS disabled";
      body = `${locatorName} turned GPS off`;
    } else if (type === "battery_low") {
      title = "Battery alert";
      body = `${locatorName} battery is low${level ? ` (${level}%)` : ""}`;
    } else if (type === "geofence_exit") {
      title = "Geofence alert";
      body = `${locatorName} left the selected area`;
    } else if (type?.startsWith("place_arrive")) {
      title = "Arrived";
      const placeName = data?.placeName?.toString() || "Place";
      body = `Arrived at ${placeName}`;
    } else if (type?.startsWith("place_left")) {
      title = "Left";
      const placeName = data?.placeName?.toString() || "Place";
      const distance = data?.distance;

      if (distance != null) {
        body = `Left ${placeName} (${Math.round(Number(distance))}m)`;
      } else {
        body = `Left ${placeName}`;
      }
    } else {
      console.log("ALERT IGNORED", requesterId, alertId, type);
      return;
    }

    await admin.messaging().send({
      topic: requesterId,
      data: {
        type: type ?? "",
        alertId,
        requesterId,
        locatorId,
        locatorName,
        level,
        placeName: data?.placeName?.toString() ?? "",
        distance: data?.distance?.toString() ?? "",
        radiusMeters: data?.radiusMeters?.toString() ?? "",
      },
      notification: {
        title,
        body,
      },
      android: {
        priority: "high",
        collapseKey: type ?? "alert",
      },
    });
  },
);
