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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.somyun.memo.data.AttachmentStorage
import com.somyun.memo.data.GitHubUploader
import com.somyun.memo.data.Memo
import com.somyun.memo.data.MemoRepository
import com.somyun.memo.data.StoredAttachment
import com.somyun.memo.ui.theme.MemoTheme
import com.somyun.memo.widget.MemoWidgetProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ShareReceiverActivity : ComponentActivity() {

    private lateinit var repository: MemoRepository
    private val gitHubUploader = GitHubUploader()
    private val backgroundScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

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
                    onCreateMemo = { attachFiles(createMemoFromShareText(), uris) },
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

    private fun createMemoFromShareText(): Memo {
        val id = System.currentTimeMillis().toString(36) +
                (Math.random() * 100000).toLong().toString(36)
        val text = intent.getStringExtra(Intent.EXTRA_TEXT).orEmpty()
        return Memo(id = id, text = text)
    }

    private fun attachFiles(memo: Memo, uris: List<Uri>) {
        MainScope().launch {
            try {
                val stored = withContext(Dispatchers.IO) {
                    uris.mapNotNull { AttachmentStorage.copyToInternalStorage(applicationContext, it) }
                }
                if (stored.isEmpty()) {
                    Toast.makeText(this@ShareReceiverActivity, "첨부할 파일을 읽지 못했습니다", Toast.LENGTH_SHORT).show()
                    finish()
                    return@launch
                }

                val updatedMemo = memo.withLocalAttachments(stored)
                repository.saveMemo(updatedMemo)
                MemoWidgetProvider.updateAllWidgets(applicationContext)
                Toast.makeText(this@ShareReceiverActivity, "첨부 완료!", Toast.LENGTH_SHORT).show()

                uploadInBackground(updatedMemo.id, stored)
            } catch (e: Exception) {
                Toast.makeText(this@ShareReceiverActivity, "첨부 실패: ${e.message}", Toast.LENGTH_SHORT).show()
            }
            finish()
        }
    }

    private fun uploadInBackground(memoId: String, attachments: List<StoredAttachment>) {
        backgroundScope.launch {
            val token = runCatching { repository.loadGithubToken() }.getOrNull() ?: return@launch
            attachments.forEach { attachment ->
                runCatching {
                    val bytes = AttachmentStorage.readBytes(applicationContext, attachment.uri) ?: return@runCatching
                    val remoteUrl = if (AttachmentStorage.isImage(attachment)) {
                        gitHubUploader.uploadImage(bytes, token)
                    } else {
                        gitHubUploader.uploadFile(bytes, attachment.name, token)
                    }
                    replaceAttachmentUrl(memoId, attachment.uri, remoteUrl)
                }
            }
        }
    }

    private suspend fun replaceAttachmentUrl(memoId: String, localUri: String, remoteUrl: String) {
        val current = repository.getMemo(memoId) ?: return
        val updated = current.copy(
            images = current.images.map { if (it == localUri) remoteUrl else it },
            files = current.files.map { file ->
                if (file["url"] == localUri) file + ("url" to remoteUrl) else file
            },
            updated = System.currentTimeMillis()
        )
        repository.saveMemo(updated)
        MemoWidgetProvider.updateAllWidgets(applicationContext)
    }

    private fun Memo.withLocalAttachments(attachments: List<StoredAttachment>): Memo {
        var updated = this
        attachments.forEach { attachment ->
            updated = if (AttachmentStorage.isImage(attachment)) {
                updated.copy(images = updated.images + attachment.uri)
            } else {
                updated.copy(files = updated.files + mapOf("name" to attachment.name, "url" to attachment.uri))
            }
        }
        return updated.copy(updated = System.currentTimeMillis())
    }

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun ShareMemoSelector(
        uris: List<Uri>,
        onCreateMemo: () -> Unit,
        onMemoSelected: (Memo) -> Unit,
        onCancel: () -> Unit
    ) {
        var memos by remember { mutableStateOf<List<Memo>>(emptyList()) }
        var isLoading by remember { mutableStateOf(true) }

        LaunchedEffect(Unit) {
            repository.observeMemos().collect {
                memos = it.sortedByDescending { memo -> memo.updated }
                isLoading = false
            }
        }

        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text("어떤 메모에 첨부할까요?", fontSize = 16.sp) },
                    navigationIcon = {
                        IconButton(onClick = onCancel) {
                            Icon(Icons.Default.Close, contentDescription = "닫기")
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
                    item {
                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onCreateMemo() },
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.primaryContainer
                            )
                        ) {
                            Row(
                                modifier = Modifier.padding(14.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(Icons.Default.Add, contentDescription = null)
                                Spacer(Modifier.width(8.dp))
                                Text("새 메모카드로 첨부", fontSize = 15.sp)
                            }
                        }
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
