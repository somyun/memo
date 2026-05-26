package com.somyun.memo.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.RemoteViews
import com.somyun.memo.MainActivity
import com.somyun.memo.R
import com.somyun.memo.data.MemoRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 홈 화면 위젯 — 선택한 메모의 내용을 표시
 *
 * 전통적 AppWidgetProvider + RemoteViews 방식으로 구현.
 * 위젯 데이터는 MemoRepository를 통해 Firestore에서 가져옵니다.
 */
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
                    updateWidget(context, appWidgetManager, id)
                }
            } catch (e: Exception) {
                Log.e(TAG, "위젯 갱신 실패: ${e.message}")
            } finally {
                pendingResult.finish()
            }
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val editor = prefs.edit()
        for (id in appWidgetIds) {
            editor.remove("${KEY_PREFIX}$id")
        }
        editor.apply()
    }

    companion object {
        private const val TAG = "MemoWidget"
        private const val PREFS_NAME = "widget_prefs"
        private const val KEY_PREFIX = "widget_memo_id_"

        /**
         * 단일 위젯 갱신
         */
        private suspend fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val memoId = prefs.getString("${KEY_PREFIX}$appWidgetId", null)

            val views = RemoteViews(context.packageName, R.layout.widget_memo)

            if (memoId != null) {
                try {
                    val repository = MemoRepository(context)
                    val memo = repository.getMemo(memoId)

                    if (memo != null) {
                        views.setTextViewText(R.id.widget_text, memo.text.ifEmpty { "(빈 메모)" })

                        if (memo.updated > 0) {
                            val sdf = SimpleDateFormat("MM.dd HH:mm", Locale.getDefault())
                            views.setTextViewText(R.id.widget_date, sdf.format(Date(memo.updated)))
                        } else {
                            views.setTextViewText(R.id.widget_date, "")
                        }
                    } else {
                        views.setTextViewText(R.id.widget_text, "삭제된 메모")
                        views.setTextViewText(R.id.widget_date, "")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "메모 로딩 실패: ${e.message}")
                    views.setTextViewText(R.id.widget_text, "로딩 실패")
                    views.setTextViewText(R.id.widget_date, "")
                }
            } else {
                views.setTextViewText(R.id.widget_text, "메모를 선택하세요")
                views.setTextViewText(R.id.widget_date, "")
            }

            // 위젯 클릭 → MainActivity 실행
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context, appWidgetId, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        /**
         * 모든 위젯 인스턴스를 갱신
         */
        suspend fun updateAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(
                ComponentName(context, MemoWidgetProvider::class.java)
            )
            for (id in ids) {
                updateWidget(context, appWidgetManager, id)
            }
        }
    }
}
