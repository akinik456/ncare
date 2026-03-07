import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

admin.initializeApp();

export const onRequestCreated = onDocumentCreated(
  { document: "requesters/{requesterId}/requests/{requestId}", region: "us-central1" },
  async (event) => {
    const requestId = event.params.requestId;
    console.log("REQUEST TRIGGERED", requestId);

    await admin.messaging().send({
      topic: "test",
      data: { type: "rl", requestId },
      android: { priority: "high" },
    });
  }
);