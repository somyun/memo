package com.somyun.memo.widget

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.lifecycleScope
import com.somyun.memo.data.Memo
import com.somyun.memo.data.MemoRepository
import com.somyun.memo.ui.theme.MemoTheme
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.*

/**
 * 위젯 추가 시 메모를 선택하는 설정 액티비티
 */
class MemoWidgetConfigActivity : ComponentActivity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private lateinit var repository: MemoRepository

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        repository = MemoRepository(applicationContext)

        // 결과를 CANCELED로 초기화 (사용자가 취소하면 위젯 추가 안 됨)
        setResult(Activity.RESULT_CANCELED)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        setContent {
            MemoTheme {
                MemoSelectorScreen(
                    onMemoSelected = { memo -> saveAndFinish(memo) },
                    onCancel = { finish() }
                )
            }
        }
    }

    private fun saveAndFinish(memo: Memo) {
        // 1. SharedPreferences에 메모 ID 저장
        val prefs = getSharedPreferences("widget_prefs", MODE_PRIVATE)
        prefs.edit()
            .putString("widget_memo_id_$appWidgetId", memo.id)
            .commit()

        // 2. 결과 설정
        val resultIntent = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        setResult(Activity.RESULT_OK, resultIntent)
        Toast.makeText(this, "위젯이 추가되었습니다", Toast.LENGTH_SHORT).show()

        // 3. 위젯 갱신 후 액티비티 종료
        lifecycleScope.launch {
            try {
                MemoWidgetProvider.updateAllWidgets(applicationContext)
            } catch (_: Exception) { }
            finish()
        }
    }

    @Composable
    fun MemoSelectorScreen(onMemoSelected: (Memo) -> Unit, onCancel: () -> Unit) {
        var memos by remember { mutableStateOf<List<Memo>>(emptyList()) }
        var isLoading by remember { mutableStateOf(true) }

        LaunchedEffect(Unit) {
            repository.observeMemos().collect {
                memos = it.sortedWith(compareByDescending<Memo> { m -> m.pinned }.thenByDescending { m -> m.updated })
                isLoading = false
            }
        }

        Scaffold(
            topBar = {
                @OptIn(ExperimentalMaterial3Api::class)
                TopAppBar(
                    title = { Text("위젯에 표시할 메모 선택", fontSize = 16.sp) },
                    navigationIcon = {
                        IconButton(onClick = onCancel) { Text("✕", fontSize = 18.sp) }
                    }
                )
            }
        ) { padding ->
            if (isLoading) {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            } else if (memos.isEmpty()) {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    Text("메모가 없습니다.\n먼저 앱에서 메모를 작성하세요.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentPadding = PaddingValues(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(memos) { memo ->
                        Card(
                            modifier = Modifier.fillMaxWidth().clickable { onMemoSelected(memo) },
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
                        ) {
                            Row(
                                modifier = Modifier.padding(12.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                if (memo.pinned) {
                                    Text("📌 ", fontSize = 14.sp)
                                }
                                Column(Modifier.weight(1f)) {
                                    Text(
                                        memo.text.ifEmpty { "(빈 메모)" },
                                        maxLines = 2,
                                        overflow = TextOverflow.Ellipsis,
                                        fontSize = 14.sp
                                    )
                                    val sdf = SimpleDateFormat("yyyy.MM.dd HH:mm", Locale.getDefault())
                                    Text(
                                        sdf.format(Date(memo.updated)),
                                        fontSize = 10.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
