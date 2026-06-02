const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

exports.onMemoUpdate = onDocumentWritten("memos/{memoId}", async (event) => {
  const memoId = event.params.memoId;
  const after = event.data?.after;
  const deleted = !after?.exists;
  const memo = deleted ? null : after.data();

  console.log(`Memo changed: ${memoId}, deleted=${deleted}`);

  try {
    const devicesSnapshot = await getFirestore().collection("devices").get();
    const tokens = devicesSnapshot.docs
      .map((doc) => doc.data().fcmToken)
      .filter((token) => !!token);

    if (tokens.length === 0) {
      console.log("No registered devices");
      return;
    }

    const data = {
      action: "widget_update",
      memoId,
      deleted: String(deleted),
    };

    if (memo) {
      data.text = String(memo.text ?? "").slice(0, 3500);
      data.updated = String(normalizeMillis(memo.updated));
    }

    const response = await getMessaging().sendEachForMulticast({
      data,
      android: {
        priority: "high",
      },
      tokens,
    });

    console.log(
      `FCM sent: success ${response.successCount}, failure ${response.failureCount}`
    );

    if (response.failureCount > 0) {
      await removeFailedTokens(tokens, response.responses);
    }
  } catch (error) {
    console.error("FCM send failed:", error);
  }
});

function normalizeMillis(value) {
  if (!value) {
    return Date.now();
  }
  if (typeof value === "number") {
    return value;
  }
  if (typeof value.toMillis === "function") {
    return value.toMillis();
  }
  return Date.now();
}

async function removeFailedTokens(tokens, responses) {
  const failedTokens = [];
  responses.forEach((response, index) => {
    if (!response.success) {
      failedTokens.push(tokens[index]);
    }
  });

  for (const token of failedTokens) {
    const docs = await getFirestore()
      .collection("devices")
      .where("fcmToken", "==", token)
      .get();
    docs.forEach((doc) => doc.ref.delete());
  }
}
