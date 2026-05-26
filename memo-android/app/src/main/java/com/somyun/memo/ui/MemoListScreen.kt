package com.somyun.memo.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.somyun.memo.data.Memo
import com.somyun.memo.ui.theme.*
import java.text.SimpleDateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MemoListScreen(viewModel: MemoViewModel) {
    val state by viewModel.uiState.collectAsState()
    var showSearch by remember { mutableStateOf(false) }
    var showSortMenu by remember { mutableStateOf(false) }

    val listState = rememberLazyListState()
    var activeEditingMemoId by remember { mutableStateOf<String?>(null) }
    var newlyCreatedMemoId by remember { mutableStateOf<String?>(null) }
    var lastIndex by remember { mutableStateOf(-1) }

    LaunchedEffect(state.memos, activeEditingMemoId, newlyCreatedMemoId) {
        newlyCreatedMemoId?.let { id ->
            val index = state.memos.indexOfFirst { it.id == id }
            if (index != -1) {
                listState.animateScrollToItem(index)
                activeEditingMemoId = id
            }
            return@LaunchedEffect
        }

        activeEditingMemoId?.let { id ->
            val index = state.memos.indexOfFirst { it.id == id }
            if (index != -1 && index != lastIndex) {
                lastIndex = index
                listState.animateScrollToItem(index)
            }
        } ?: run {
            lastIndex = -1
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    if (showSearch) {
                        OutlinedTextField(
                            value = state.searchQuery,
                            onValueChange = { viewModel.setSearchQuery(it) },
                            placeholder = { Text("검색...", fontSize = 14.sp) },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                            textStyle = TextStyle(fontSize = 14.sp)
                        )
                    } else {
                        Column {
                            Text("memo", style = MaterialTheme.typography.titleLarge)
                            if (state.statusMessage.isNotEmpty()) {
                                Text(
                                    state.statusMessage,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                },
                actions = {
                    IconButton(onClick = {
                        showSearch = !showSearch
                        if (!showSearch) viewModel.setSearchQuery("")
                    }) {
                        Icon(
                            if (showSearch) Icons.Default.Close else Icons.Default.Search,
                            contentDescription = "검색"
                        )
                    }
                    Box {
                        IconButton(onClick = { showSortMenu = true }) {
                            Icon(Icons.Default.Sort, contentDescription = "정렬")
                        }
                        DropdownMenu(
                            expanded = showSortMenu,
                            onDismissRequest = { showSortMenu = false }
                        ) {
                            SortOrder.entries.forEach { order ->
                                DropdownMenuItem(
                                    text = {
                                        Text(
                                            order.label,
                                            fontWeight = if (order == state.sortOrder)
                                                androidx.compose.ui.text.font.FontWeight.Bold else null
                                        )
                                    },
                                    onClick = {
                                        viewModel.setSortOrder(order)
                                        showSortMenu = false
                                    },
                                    leadingIcon = {
                                        if (order == state.sortOrder)
                                            Icon(Icons.Default.Check, null, tint = MaterialTheme.colorScheme.primary)
                                    }
                                )
                            }
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background
                )
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = {
                    val newMemo = viewModel.createMemo()
                    newlyCreatedMemoId = newMemo.id
                },
                containerColor = MaterialTheme.colorScheme.primary
            ) {
                Icon(Icons.Default.Add, contentDescription = "새 메모", tint = MaterialTheme.colorScheme.onPrimary)
            }
        }
    ) { padding ->
        if (state.isLoading) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        } else if (state.memos.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text(
                    if (state.searchQuery.isNotEmpty()) "검색 결과 없음" else "메모가 없습니다\n+ 버튼을 눌러 추가하세요",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodyLarge
                )
            }
        } else {
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(top = padding.calculateTopPadding())
                    .imePadding()
                    .navigationBarsPadding()
                    .background(MaterialTheme.colorScheme.background),
                contentPadding = PaddingValues(12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(state.memos, key = { it.id }) { memo ->
                    MemoCard(
                        memo = memo,
                        onTextChange = { viewModel.updateMemoText(memo, it) },
                        onDelete = { viewModel.deleteMemo(memo) },
                        onTogglePin = { viewModel.togglePin(memo) },
                        onRemoveImage = { url -> viewModel.removeImage(memo, url) },
                        onRemoveFile = { url -> viewModel.removeFile(memo, url) },
                        onFocus = { activeEditingMemoId = memo.id },
                        shouldAutoFocus = newlyCreatedMemoId == memo.id,
                        onAutoFocusHandled = { newlyCreatedMemoId = null }
                    )
                }
            }
        }
    }
}

@Composable
fun MemoCard(
    memo: Memo,
    onTextChange: (String) -> Unit,
    onDelete: () -> Unit,
    onTogglePin: () -> Unit,
    onRemoveImage: (String) -> Unit,
    onRemoveFile: (String) -> Unit,
    onFocus: () -> Unit,
    shouldAutoFocus: Boolean = false,
    onAutoFocusHandled: () -> Unit = {}
) {
    var showDeleteConfirm by remember { mutableStateOf(false) }
    var text by remember(memo.id) { mutableStateOf(memo.text) }
    val focusRequester = remember { FocusRequester() }
 
    // 외부 변경 반영 (다른 기기에서 수정)
    LaunchedEffect(memo.text) {
        if (memo.text != text) text = memo.text
    }

    LaunchedEffect(shouldAutoFocus) {
        if (shouldAutoFocus) {
            focusRequester.requestFocus()
            onAutoFocusHandled()
        }
    }

    Card(
        modifier = Modifier
            .fillMaxWidth(),
        shape = RoundedCornerShape(6.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            // 상단: 고정 아이콘 + 삭제 버튼
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (memo.pinned) {
                    Icon(
                        Icons.Default.PushPin,
                        contentDescription = "고정됨",
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(16.dp)
                    )
                } else {
                    Spacer(Modifier.width(16.dp))
                }
                Row {
                    IconButton(onClick = { onTogglePin() }, modifier = Modifier.size(28.dp)) {
                        Icon(
                            if (memo.pinned) Icons.Default.PushPin else Icons.Outlined.PushPin,
                            contentDescription = "고정",
                            modifier = Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    IconButton(onClick = { showDeleteConfirm = true }, modifier = Modifier.size(28.dp)) {
                        Icon(
                            Icons.Default.Close,
                            contentDescription = "삭제",
                            modifier = Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            // 텍스트 입력
            BasicTextField(
                value = text,
                onValueChange = {
                    text = it
                    onTextChange(it)
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 80.dp)
                    .focusRequester(focusRequester)
                    .onFocusChanged { focusState ->
                        if (focusState.isFocused) {
                            onFocus()
                        }
                    },
                textStyle = TextStyle(
                    color = MaterialTheme.colorScheme.onSurface,
                    fontSize = 14.sp,
                    lineHeight = 20.sp
                ),
                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                decorationBox = { inner ->
                    if (text.isEmpty()) {
                        Text("메모 입력...", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp)
                    }
                    inner()
                }
            )

            // 이미지 목록
            if (memo.images.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                memo.images.forEach { url ->
                    ImageAttachment(url = url, onRemove = { onRemoveImage(url) })
                }
            }

            // 파일 목록
            if (memo.files.isNotEmpty()) {
                Spacer(Modifier.height(6.dp))
                memo.fileAttachments.forEach { file ->
                    FileAttachmentRow(file.name, file.url, onRemove = { onRemoveFile(file.url) })
                }
            }

            // 하단: 수정 날짜
            Spacer(Modifier.height(8.dp))
            Text(
                formatDate(memo.updated),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.align(Alignment.End),
                fontSize = 10.sp
            )
        }
    }

    // 삭제 확인 다이얼로그
    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("메모 삭제") },
            text = { Text("이 메모를 삭제할까요?") },
            confirmButton = {
                TextButton(onClick = { showDeleteConfirm = false; onDelete() }) {
                    Text("삭제", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("취소") }
            }
        )
    }
}

@Composable
fun ImageAttachment(url: String, onRemove: () -> Unit) {
    var showDeleteConfirm by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp)
            .clip(RoundedCornerShape(4.dp))
    ) {
        AsyncImage(
            model = url,
            contentDescription = "첨부 이미지",
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 200.dp)
                .clip(RoundedCornerShape(4.dp)),
            contentScale = ContentScale.Crop
        )
        IconButton(
            onClick = { showDeleteConfirm = true },
            modifier = Modifier
                .align(Alignment.TopEnd)
                .size(24.dp)
                .background(Color.Black.copy(alpha = 0.5f), RoundedCornerShape(12.dp))
        ) {
            Icon(Icons.Default.Close, "삭제", tint = Color.White, modifier = Modifier.size(14.dp))
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("이미지 삭제") },
            text = { Text("이 이미지를 삭제할까요?\nGitHub에 업로드된 파일도 함께 삭제됩니다.") },
            confirmButton = {
                TextButton(onClick = { showDeleteConfirm = false; onRemove() }) {
                    Text("삭제", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("취소") }
            }
        )
    }
}

@Composable
fun FileAttachmentRow(name: String, url: String, onRemove: () -> Unit) {
    val uriHandler = LocalUriHandler.current
    var showDeleteConfirm by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp)
            .background(
                MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f),
                RoundedCornerShape(4.dp)
            )
            .padding(horizontal = 8.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text("📎", fontSize = 13.sp)
        Spacer(Modifier.width(6.dp))
        Text(
            text = name,
            modifier = Modifier
                .weight(1f)
                .clickable { uriHandler.openUri(url) },
            color = LinkBlue,
            fontSize = 12.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        IconButton(onClick = { showDeleteConfirm = true }, modifier = Modifier.size(20.dp)) {
            Icon(Icons.Default.Close, "삭제", modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }

    if (showDeleteConfirm) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = { Text("파일 삭제") },
            text = { Text("\"$name\" 첨부를 삭제할까요?\nGitHub에 업로드된 파일도 함께 삭제됩니다.") },
            confirmButton = {
                TextButton(onClick = { showDeleteConfirm = false; onRemove() }) {
                    Text("삭제", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) { Text("취소") }
            }
        )
    }
}

private fun formatDate(ts: Long): String {
    if (ts == 0L) return ""
    val sdf = SimpleDateFormat("yyyy.MM.dd HH:mm", Locale.getDefault())
    return sdf.format(Date(ts))
}
