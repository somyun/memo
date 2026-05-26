package com.somyun.memo.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.glance.*
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.layout.*
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.google.firebase.firestore.FirebaseFirestore
import com.somyun.memo.MainActivity
import kotlinx.coroutines.tasks.await

// Glance State 키
private val KEY_TEXT = stringPreferencesKey("memo_text")
private val KEY_DATE = stringPreferencesKey("memo_date")

/**
 * 홈 화면 위젯 — 선택한 메모의 내용을 표시
 *
 * Glance State 기반: 외부에서 updateAppWidgetState()로 데이터를 먼저 넣은 후
 * update()를 호출하면, 세션이 이미 실행 중이어도(session.updateGlance() 경로)
 * currentState에서 최신 데이터를 읽어 올바르게 갱신됩니다.
 */
class MemoWidget : GlanceAppWidget() {

    override val stateDefinition = PreferencesGlanceStateDefinition

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        // 최초 세션 시작 시에도 상태 갱신
        refreshState(context, id)

        provideContent {
            val state = currentState<Preferences>()
            val text = state[KEY_TEXT] ?: "메모를 선택하세요"
            val date = state[KEY_DATE] ?: ""
            MemoWidgetContent(text, date)
        }
    }

    @Composable
    fun MemoWidgetContent(text: String, date: String) {
        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .padding(2.dp)
                .clickable(actionStartActivity<MainActivity>())
                .background(Color(0xFFFEF9C3))
                .cornerRadius(12.dp)
        ) {
            Column(
                modifier = GlanceModifier
                    .fillMaxSize()
                    .padding(12.dp)
            ) {
                Text(
                    text = text,
                    style = TextStyle(
                        color = ColorProvider(Color(0xFF2B2B2B)),
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Normal
                    ),
                    modifier = GlanceModifier.fillMaxWidth().defaultWeight(),
                    maxLines = 30
                )

                if (date.isNotEmpty()) {
                    Text(
                        text = date,
                        style = TextStyle(
                            color = ColorProvider(Color(0xFFAAAAAA)),
                            fontSize = 10.sp
                        ),
                        modifier = GlanceModifier.fillMaxWidth()
                    )
                }
            }
        }
    }

    companion object {
        /**
         * 위젯 상태를 Firestore에서 가져와 Glance State에 저장
         * update() 호출 전에 반드시 이 함수를 먼저 실행해야 합니다.
         */
        suspend fun refreshState(context: Context, glanceId: GlanceId) {
            val appWidgetId = GlanceAppWidgetManager(context).getAppWidgetId(glanceId)
            val prefs = context.getSharedPreferences("widget_prefs", Context.MODE_PRIVATE)
            val memoId = prefs.getString("widget_memo_id_$appWidgetId", null)

            updateAppWidgetState(context, PreferencesGlanceStateDefinition, glanceId) { state ->
                val mutablePrefs = state.toMutablePreferences()
                if (memoId != null) {
                    try {
                        val doc = FirebaseFirestore.getInstance()
                            .collection("memos").document(memoId).get().await()
                        mutablePrefs[KEY_TEXT] = doc.getString("text") ?: "(빈 메모)"
                        val updated = doc.getLong("updated") ?: 0L
                        if (updated > 0) {
                            val sdf = java.text.SimpleDateFormat("MM.dd HH:mm", java.util.Locale.getDefault())
                            mutablePrefs[KEY_DATE] = sdf.format(java.util.Date(updated))
                        } else {
                            mutablePrefs[KEY_DATE] = ""
                        }
                    } catch (_: Exception) {
                        mutablePrefs[KEY_TEXT] = "로딩 실패"
                        mutablePrefs[KEY_DATE] = ""
                    }
                } else {
                    mutablePrefs[KEY_TEXT] = "메모를 선택하세요"
                    mutablePrefs[KEY_DATE] = ""
                }
                mutablePrefs.toPreferences()
            }
        }

        /**
         * 모든 위젯의 상태를 갱신하고 UI를 업데이트
         */
        suspend fun refreshAndUpdateAll(context: Context) {
            val manager = GlanceAppWidgetManager(context)
            val glanceIds = manager.getGlanceIds(MemoWidget::class.java)
            for (glanceId in glanceIds) {
                refreshState(context, glanceId)
                MemoWidget().update(context, glanceId)
            }
        }
    }
}

/**
 * 위젯 수신자 (시스템이 호출)
 */
class MemoWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = MemoWidget()
}
