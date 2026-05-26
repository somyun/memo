package com.somyun.memo

import android.content.Intent
import android.net.Uri
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
import com.somyun.memo.data.Memo
import com.somyun.memo.data.MemoRepository
import com.somyun.memo.data.GitHubUploader
import com.somyun.memo.widget.MemoWidgetProvider
import com.somyun.memo.ui.theme.MemoTheme
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.*

/**
 * 다른 앱에서 "공유"를 통해 파일/이미지를 받는 액티비티
 */
class ShareReceiverActivity : ComponentActivity() {

    private lateinit var repository: MemoRepository
    private val gitHubUploader = GitHubUploader()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        repository = MemoRepository(applicationContext)

        val uris = extractUris(intent)
        if (uris.isEmpty()) {
            Toast.makeText(this, "공유된 파일이 없습니다", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        setContent {
            MemoTheme {
                ShareMemoSelector(
                    uris = uris,
                    onMemoSelected = { memo -> attachFiles(memo, uris) },
                    onCancel = { finish() }
                )
            }
        }
    }

    private fun extractUris(intent: Intent): List<Uri> {
        val uris = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> {
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.add(it) }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.addAll(it) }
            }
        }
        return uris
    }

    private fun attachFiles(memo: Memo, uris: List<Uri>) {
        val scope = kotlinx.coroutines.MainScope()
        scope.launch {
            try {
                val token = repository.loadGithubToken()
                var updatedMemo = memo

                for (uri in uris) {
                    val bytes = contentResolver.openInputStream(uri)?.readBytes() ?: continue
                    val mimeType = contentResolver.getType(uri) ?: ""
                    val fileName = getFileName(uri)

                    if (mimeType.startsWith("image/")) {
                        val url = gitHubUploader.uploadImage(bytes, token)
                        updatedMemo = updatedMemo.copy(
                            images = updatedMemo.images + url,
                            updated = System.currentTimeMillis()
                        )
                    } else {
                        val url = gitHubUploader.uploadFile(bytes, fileName, token)
                        val fileEntry = mapOf("name" to fileName, "url" to url)
                        updatedMemo = updatedMemo.copy(
                            files = updatedMemo.files + fileEntry,
                            updated = System.currentTimeMillis()
                        )
                    }
                }

                repository.saveMemo(updatedMemo)
                MemoWidgetProvider.updateAllWidgets(this@ShareReceiverActivity.applicationContext)
                Toast.makeText(this@ShareReceiverActivity, "첨부 완료!", Toast.LENGTH_SHORT).show()
            } catch (e: Exception) {
                Toast.makeText(this@ShareReceiverActivity, "첨부 실패: ${e.message}", Toast.LENGTH_SHORT).show()
            }
            finish()
        }
    }

    private fun getFileName(uri: Uri): String {
        var name = "file"
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val idx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
            if (idx >= 0 && cursor.moveToFirst()) {
                name = cursor.getString(idx) ?: "file"
            }
        }
        return name
    }

    @Composable
    fun ShareMemoSelector(uris: List<Uri>, onMemoSelected: (Memo) -> Unit, onCancel: () -> Unit) {
        var memos by remember { mutableStateOf<List<Memo>>(emptyList()) }
        var isLoading by remember { mutableStateOf(true) }

        LaunchedEffect(Unit) {
            repository.observeMemos().collect {
                memos = it.sortedByDescending { m -> m.updated }
                isLoading = false
            }
        }

        Scaffold(
            topBar = {
                @OptIn(ExperimentalMaterial3Api::class)
                TopAppBar(
                    title = { Text("어떤 메모에 첨부할까요?", fontSize = 16.sp) },
                    navigationIcon = {
                        IconButton(onClick = onCancel) {
                            Text("✕", fontSize = 18.sp)
                        }
                    }
                )
            }
        ) { padding ->
            if (isLoading) {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(padding),
                    contentPadding = PaddingValues(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    item {
                        Text(
                            "${uris.size}개 파일을 첨부할 메모를 선택하세요",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(bottom = 8.dp)
                        )
                    }
                    items(memos) { memo ->
                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onMemoSelected(memo) },
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
                        ) {
                            Column(Modifier.padding(12.dp)) {
                                Text(
                                    memo.text.ifEmpty { "(빈 메모)" },
                                    maxLines = 3,
                                    overflow = TextOverflow.Ellipsis,
                                    fontSize = 14.sp
                                )
                                val sdf = SimpleDateFormat("yyyy.MM.dd HH:mm", Locale.getDefault())
                                Text(
                                    sdf.format(Date(memo.updated)),
                                    fontSize = 10.sp,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.align(Alignment.End)
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
