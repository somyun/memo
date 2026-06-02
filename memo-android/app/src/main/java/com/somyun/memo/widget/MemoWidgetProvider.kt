package com.somyun.memo.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.RemoteViews
import com.google.firebase.firestore.Source
import com.somyun.memo.MainActivity
import com.somyun.memo.R
import com.somyun.memo.data.Memo
import com.somyun.memo.data.MemoRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MemoWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val pendingResult = goAsync()
        CoroutineScope(Dispatchers.IO).launch {
            try {
                for (id in appWidgetIds) {
                    updateWidgetFromRepository(context, appWidgetManager, id)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Widget update failed", e)
            } finally {
                pendingResult.finish()
            }
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val editor = prefs.edit()
        for (id in appWidgetIds) {
            editor.remove(memoIdKey(id))
            editor.remove(textKey(id))
            editor.remove(dateKey(id))
        }
        editor.apply()
    }

    companion object {
        private const val TAG = "MemoWidget"
        private const val PREFS_NAME = "widget_prefs"
        private const val KEY_MEMO_ID_PREFIX = "widget_memo_id_"
        private const val KEY_TEXT_PREFIX = "widget_text_"
        private const val KEY_DATE_PREFIX = "widget_date_"

        private fun memoIdKey(appWidgetId: Int) = "$KEY_MEMO_ID_PREFIX$appWidgetId"
        private fun textKey(appWidgetId: Int) = "$KEY_TEXT_PREFIX$appWidgetId"
        private fun dateKey(appWidgetId: Int) = "$KEY_DATE_PREFIX$appWidgetId"

        suspend fun updateAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(
                ComponentName(context, MemoWidgetProvider::class.java)
            )
            for (id in ids) {
                updateWidgetFromRepository(context, appWidgetManager, id)
            }
        }

        fun updateWidgetsForMemo(context: Context, memo: Memo) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(
                ComponentName(context, MemoWidgetProvider::class.java)
            )
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            for (id in ids) {
                if (prefs.getString(memoIdKey(id), null) == memo.id) {
                    renderWidget(context, appWidgetManager, id, memo)
                }
            }
        }

        fun updateWidgetsForMemos(context: Context, memos: List<Memo>) {
            val memosById = memos.associateBy { it.id }
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(
                ComponentName(context, MemoWidgetProvider::class.java)
            )
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            for (id in ids) {
                val memoId = prefs.getString(memoIdKey(id), null) ?: continue
                val memo = memosById[memoId] ?: continue
                renderWidget(context, appWidgetManager, id, memo)
            }
        }

        private suspend fun updateWidgetFromRepository(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val memoId = prefs.getString(memoIdKey(appWidgetId), null)

            if (memoId == null) {
                renderMessage(context, appWidgetManager, appWidgetId, "메모를 선택하세요", "")
                return
            }

            val repository = MemoRepository(context)
            val memo = runCatching { repository.getMemo(memoId) }
                .recoverCatching { error ->
                    Log.w(TAG, "Server read failed for widget $appWidgetId, trying cache", error)
                    repository.getMemo(memoId, Source.CACHE)
                }
                .getOrElse { error ->
                    Log.e(TAG, "Memo load failed for widget $appWidgetId", error)
                    renderCachedOrMessage(context, appWidgetManager, appWidgetId)
                    return
                }

            if (memo == null) {
                renderMessage(context, appWidgetManager, appWidgetId, "삭제된 메모", "")
                return
            }

            renderWidget(context, appWidgetManager, appWidgetId, memo)
        }

        private fun renderWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            memo: Memo
        ) {
            val text = memo.text.ifEmpty { "(빈 메모)" }
            val date = if (memo.updated > 0) {
                SimpleDateFormat("MM.dd HH:mm", Locale.getDefault()).format(Date(memo.updated))
            } else {
                ""
            }

            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(textKey(appWidgetId), text)
                .putString(dateKey(appWidgetId), date)
                .apply()

            renderMessage(context, appWidgetManager, appWidgetId, text, date)
        }

        private fun renderCachedOrMessage(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val cachedText = prefs.getString(textKey(appWidgetId), null)
            val cachedDate = prefs.getString(dateKey(appWidgetId), "") ?: ""
            if (cachedText != null) {
                renderMessage(context, appWidgetManager, appWidgetId, cachedText, cachedDate)
            } else {
                renderMessage(context, appWidgetManager, appWidgetId, "메모를 불러올 수 없습니다", "")
            }
        }

        private fun renderMessage(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            text: String,
            date: String
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_memo).apply {
                setTextViewText(R.id.widget_text, text)
                setTextViewText(R.id.widget_date, date)
                setOnClickPendingIntent(
                    R.id.widget_root,
                    PendingIntent.getActivity(
                        context,
                        appWidgetId,
                        Intent(context, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                        },
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                )
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
