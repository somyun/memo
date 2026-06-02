package com.somyun.memo

import android.content.Context
import android.provider.Settings
import android.util.Log
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.somyun.memo.data.Memo
import com.somyun.memo.widget.MemoWidgetProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class MemoFirebaseMessagingService : FirebaseMessagingService() {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)

        val action = message.data["action"]
        val memoId = message.data["memoId"]
        val text = message.data["text"]
        val updated = message.data["updated"]?.toLongOrNull()
        val deleted = message.data["deleted"] == "true"

        Log.d(TAG, "Received: action=$action, memoId=$memoId, hasText=${text != null}, deleted=$deleted")

        if (action != "widget_update" && action != "memo_updated" && memoId == null) {
            return
        }

        if (!deleted && memoId != null && text != null) {
            MemoWidgetProvider.updateWidgetsForMemo(
                applicationContext,
                Memo(
                    id = memoId,
                    text = text,
                    updated = updated ?: System.currentTimeMillis()
                )
            )
            return
        }

        updateAllWidgets()
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "New token: $token")
        saveFcmToken(this, token)
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }

    private fun updateAllWidgets() {
        scope.launch {
            try {
                MemoWidgetProvider.updateAllWidgets(applicationContext)
                Log.d(TAG, "Widget refresh complete")
            } catch (e: Exception) {
                Log.e(TAG, "Widget refresh failed", e)
            }
        }
    }

    companion object {
        private const val TAG = "FCM"

        fun registerToken(context: Context) {
            FirebaseMessaging.getInstance().token
                .addOnSuccessListener { token ->
                    saveFcmToken(context.applicationContext, token)
                    Log.d(TAG, "Token registered: ${token.take(20)}...")
                }
                .addOnFailureListener { error ->
                    Log.e(TAG, "Token registration failed", error)
                }
        }

        private fun saveFcmToken(context: Context, token: String) {
            val deviceId = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ANDROID_ID
            )
            FirebaseFirestore.getInstance()
                .collection("devices")
                .document(deviceId)
                .set(
                    mapOf(
                        "fcmToken" to token,
                        "updatedAt" to System.currentTimeMillis()
                    )
                )
        }
    }
}
