const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

/**
 * memos 컬렉션 문서 변경 시 → 모든 기기에 FCM 푸시 → 위젯 갱신
 */
exports.onMemoUpdate = onDocumentWritten("memos/{memoId}", async (event) => {
    const memoId = event.params.memoId;
    console.log(`메모 변경 감지: ${memoId}`);

    try {
        // 등록된 모든 기기의 FCM 토큰 조회
        const devicesSnapshot = await getFirestore().collection("devices").get();
        const tokens = devicesSnapshot.docs
            .map(doc => doc.data().fcmToken)
            .filter(token => !!token);

        if (tokens.length === 0) {
            console.log("등록된 기기 없음");
            return;
        }

        // 데이터 메시지 전송 (알림 없이, 위젯 갱신만 트리거)
        const message = {
            data: {
                action: "widget_update",
                memoId: memoId
            },
            android: {
                priority: "high"
            },
            tokens: tokens
        };

        const response = await getMessaging().sendEachForMulticast(message);
        console.log(`FCM 전송 완료: 성공 ${response.successCount}, 실패 ${response.failureCount}`);

        // 만료된 토큰 정리
        if (response.failureCount > 0) {
            const failedTokens = [];
            response.responses.forEach((resp, idx) => {
                if (!resp.success) {
                    failedTokens.push(tokens[idx]);
                }
            });
            // 실패한 토큰의 기기 문서 삭제
            for (const token of failedTokens) {
                const docs = await getFirestore()
                    .collection("devices")
                    .where("fcmToken", "==", token)
                    .get();
                docs.forEach(doc => doc.ref.delete());
            }
        }
    } catch (error) {
        console.error("FCM 전송 실패:", error);
    }
});
