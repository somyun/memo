package com.somyun.memo

import android.content.Context
import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.google.firebase.firestore.FirebaseFirestore
import com.somyun.memo.widget.MemoWidgetProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * FCM 서비스 — 다른 기기에서 메모 변경 시 위젯을 즉시 갱신
 */
class MemoFirebaseMessagingService : FirebaseMessagingService() {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)

        val action = message.data["action"]
        val memoId = message.data["memoId"]

        Log.d("FCM", "수신: action=$action, memoId=$memoId")

        // 메모가 업데이트되었다는 알림이 오면 위젯을 갱신함
        if (action == "widget_update" || action == "memo_updated" || memoId != null) {
            updateAllWidgets()
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d("FCM", "새 토큰: $token")
        // Firestore에 FCM 토큰 저장
        saveFcmToken(token)
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }

    private fun updateAllWidgets() {
        scope.launch {
            try {
                MemoWidgetProvider.updateAllWidgets(applicationContext)
                Log.d("FCM", "위젯 갱신 완료")
            } catch (e: Exception) {
                Log.e("FCM", "위젯 갱신 실패: ${e.message}")
            }
        }
    }

    private fun saveFcmToken(token: String) {
        val deviceId = android.provider.Settings.Secure.getString(
            contentResolver, android.provider.Settings.Secure.ANDROID_ID
        )
        FirebaseFirestore.getInstance()
            .collection("devices")
            .document(deviceId)
            .set(mapOf(
                "fcmToken" to token,
                "updatedAt" to System.currentTimeMillis()
            ))
    }

    companion object {
        /** 앱 시작 시 FCM 토큰을 Firestore에 등록 */
        fun registerToken(context: Context) {
            com.google.firebase.messaging.FirebaseMessaging.getInstance().token
                .addOnSuccessListener { token ->
                    val deviceId = android.provider.Settings.Secure.getString(
                        context.contentResolver, android.provider.Settings.Secure.ANDROID_ID
                    )
                    FirebaseFirestore.getInstance()
                        .collection("devices")
                        .document(deviceId)
                        .set(mapOf(
                            "fcmToken" to token,
                            "updatedAt" to System.currentTimeMillis()
                        ))
                    Log.d("FCM", "토큰 등록 완료: ${token.take(20)}...")
                }
        }
    }
}
