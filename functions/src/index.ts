import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

admin.initializeApp();

export const onRequestCreated = onDocumentCreated(
  {
    document: "requesters/{requesterId}/requests/{requestId}",
    region: "us-central1",
  },
  async (event) => {
    const requesterId = event.params.requesterId;
    const requestId = event.params.requestId;
    const data = event.data?.data();

    const locatorId = data?.locatorId?.toString();
    if (!locatorId) {
      console.log("NO LOCATOR ID", requesterId, requestId);
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
      requesterId,
      requestId,
      locatorId,
      locatorTopic,
    );

    await admin.messaging().send({
      topic: locatorTopic,
      data: {
        type: "rl",
        requestId,
        requesterId,
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
