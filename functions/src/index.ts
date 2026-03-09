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

    console.log("REQUEST TRIGGERED", requesterId, requestId, locatorId);

    await admin.messaging().send({
      topic: requesterId,
      data: {
        type: "rl",
        requestId,
        requesterId,
        locatorId,
      },
      android: { priority: "high" },
    });
  }
);
