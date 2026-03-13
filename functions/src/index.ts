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

    if (type !== "call_me") {
      console.log("ALERT IGNORED", requesterId, alertId, type);
      return;
    }

    console.log("CALL_ME ALERT", requesterId, alertId, locatorId, locatorName);

    await admin.messaging().send({
      topic: requesterId,
      data: {
        type: "call_me",
        alertId,
        requesterId,
        locatorId,
        locatorName,
      },
      android: { priority: "high" ,
	  });
  },
);
