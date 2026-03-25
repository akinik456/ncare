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

    if (!groupId || !locatorId || !requestId || !requesterId) {
      console.log(
        "INVALID REQUEST DATA",
        groupId,
        locatorId,
        requestId,
        requesterId,
      );
      return;
    }

    const locatorTopic = `locator_${locatorId}`;

    const requesterDeviceDoc = await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .collection("devices")
      .doc(requesterId)
      .get();

    const requesterName =
      requesterDeviceDoc.data()?.name?.toString() || "Requester";

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
    document: "groups/{groupId}/locators/{locatorId}/alerts/{alertId}",
    region: "us-central1",
  },
  async (event) => {
    const groupId = event.params.groupId;
    const locatorId = event.params.locatorId;
    const alertId = event.params.alertId;
    const data = event.data?.data();

    const type = data?.type?.toString() ?? "";
    const locatorName = data?.locatorName?.toString() ?? "Locator";
    const level = data?.level?.toString() ?? data?.battery?.toString() ?? "";
    const targetRequesterDeviceId =
      data?.requesterDeviceId?.toString() ?? "";
    const targetMode = data?.targetMode?.toString() ?? "";

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
    } else if (type.startsWith("place_arrive")) {
      title = "Arrived";
      const placeName = data?.placeName?.toString() || "Place";
      body = `Arrived at ${placeName}`;
    } else if (type.startsWith("place_left")) {
      title = "Left";
      const placeName = data?.placeName?.toString() || "Place";
      const distance = data?.distance;
      if (distance != null) {
        body = `Left ${placeName} (${Math.round(Number(distance))}m)`;
      } else {
        body = `Left ${placeName}`;
      }
    } else {
      console.log("ALERT IGNORED", groupId, locatorId, alertId, type);
      return;
    }

    const devicesSnap = await admin.firestore()
      .collection("groups")
      .doc(groupId)
      .collection("devices")
      .where("role", "==", "requester")
      .where("active", "==", true)
      .get();

    let targetDeviceIds = devicesSnap.docs.map((d) => d.id);

    if (type === "call_me") {
      if (targetMode === "single" && targetRequesterDeviceId.length > 0) {
        targetDeviceIds = targetDeviceIds.filter(
          (id: string) => id === targetRequesterDeviceId,
        );
      } else if (targetMode === "all") {
        // herkese gider
      } else {
        console.log(
          "CALL_ME IGNORED => invalid target mode",
          groupId,
          locatorId,
          alertId,
          targetMode,
          targetRequesterDeviceId,
        );
        return;
      }
    }

    if (targetDeviceIds.length === 0) {
      console.log(
        "NO TARGET REQUESTER DEVICES",
        groupId,
        locatorId,
        alertId,
        type,
        targetRequesterDeviceId,
      );
      return;
    }

    for (const requesterDeviceId of targetDeviceIds) {
      await admin.messaging().send({
        topic: requesterDeviceId,
        data: {
          type,
          alertId,
          groupId,
          locatorId,
          locatorName,
          level,
          requesterDeviceId,
          targetMode,
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
          collapseKey: type,
        },
      });
    }
  },
);
