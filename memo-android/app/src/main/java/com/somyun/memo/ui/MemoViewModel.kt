package com.somyun.memo.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.somyun.memo.data.GitHubUploader
import com.somyun.memo.data.Memo
import com.somyun.memo.data.MemoRepository
import com.somyun.memo.widget.MemoWidgetProvider
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class SortOrder(val label: String) {
    UPDATED_DESC("최근 수정순"),
    CREATED_DESC("최신 생성순"),
    CREATED_ASC("오래된 순"),
    UPDATED_ASC("오래된 수정순")
}

data class MemoUiState(
    val memos: List<Memo> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val sortOrder: SortOrder = SortOrder.UPDATED_DESC,
    val searchQuery: String = "",
    val statusMessage: String = ""
)

class MemoViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = MemoRepository(application)
    private val gitHubUploader = GitHubUploader()
    private var githubToken: String? = null
    private var saveJob: Job? = null

    private val _uiState = MutableStateFlow(MemoUiState())
    val uiState: StateFlow<MemoUiState> = _uiState.asStateFlow()

    // 원본 메모 리스트 (필터/정렬 전)
    private var rawMemos: List<Memo> = emptyList()

    init {
        observeMemos()
    }

    private fun observeMemos() {
        viewModelScope.launch {
            repository.observeMemos().collect { memos ->
                rawMemos = memos
                _uiState.value = _uiState.value.copy(
                    memos = applySortAndFilter(memos),
                    isLoading = false,
                    error = null
                )
                // 외부 변경(Firebase Console, 다른 기기 등)이 감지되었을 때 위젯도 즉시 갱신
                MemoWidgetProvider.updateWidgetsForMemos(getApplication(), memos)
            }
        }
    }

    private fun applySortAndFilter(memos: List<Memo>): List<Memo> {
        val query = _uiState.value.searchQuery.trim()
        val filtered = if (query.isEmpty()) memos
        else memos.filter {
            it.text.contains(query, ignoreCase = true) ||
                    it.fileAttachments.any { f -> f.name.contains(query, ignoreCase = true) }
        }

        val sorted = when (_uiState.value.sortOrder) {
            SortOrder.UPDATED_DESC -> filtered.sortedByDescending { it.updated }
            SortOrder.CREATED_DESC -> filtered.sortedByDescending { it.created }
            SortOrder.CREATED_ASC -> filtered.sortedBy { it.created }
            SortOrder.UPDATED_ASC -> filtered.sortedBy { it.updated }
        }

        // 고정 메모를 항상 최상단
        return sorted.sortedByDescending { it.pinned }
    }

    fun setSortOrder(order: SortOrder) {
        _uiState.value = _uiState.value.copy(sortOrder = order)
        _uiState.value = _uiState.value.copy(memos = applySortAndFilter(rawMemos))
    }

    fun setSearchQuery(query: String) {
        _uiState.value = _uiState.value.copy(searchQuery = query)
        _uiState.value = _uiState.value.copy(memos = applySortAndFilter(rawMemos))
    }

    /** 메모 텍스트 수정 (1.4초 debounce 저장) */
    fun updateMemoText(memo: Memo, newText: String) {
        val updated = memo.copy(text = newText, updated = System.currentTimeMillis())
        updateLocalMemo(updated)
        debounceSave(updated)
    }

    /** 메모 고정/해제 토글 */
    fun togglePin(memo: Memo) {
        val updated = memo.copy(pinned = !memo.pinned, updated = System.currentTimeMillis())
        updateLocalMemo(updated)
        viewModelScope.launch { repository.saveMemo(updated) }
    }

    /** 새 메모 생성 */
    fun createMemo(text: String = ""): Memo {
        val id = System.currentTimeMillis().toString(36) +
                (Math.random() * 100000).toLong().toString(36)
        val memo = Memo(id = id, text = text)
        viewModelScope.launch { repository.saveMemo(memo) }
        return memo
    }

    /** 메모 삭제 */
    fun deleteMemo(memo: Memo) {
        viewModelScope.launch { repository.deleteMemo(memo.id) }
    }

    /** 이미지 업로드 → 메모에 추가 */
    fun uploadImage(memo: Memo, imageBytes: ByteArray) {
        viewModelScope.launch {
            try {
                setStatus("이미지 업로드 중...")
                val token = getToken()
                val url = gitHubUploader.uploadImage(imageBytes, token)
                val updated = memo.copy(
                    images = memo.images + url,
                    updated = System.currentTimeMillis()
                )
                repository.saveMemo(updated)
                setStatus("업로드 완료")
                clearStatusAfterDelay()
            } catch (e: Exception) {
                setStatus("업로드 실패: ${e.message}")
            }
        }
    }

    /** 파일 업로드 → 메모에 추가 */
    fun uploadFile(memo: Memo, fileBytes: ByteArray, fileName: String) {
        viewModelScope.launch {
            try {
                setStatus("\"$fileName\" 업로드 중...")
                val token = getToken()
                val url = gitHubUploader.uploadFile(fileBytes, fileName, token)
                val fileEntry = mapOf("name" to fileName, "url" to url)
                val updated = memo.copy(
                    files = memo.files + fileEntry,
                    updated = System.currentTimeMillis()
                )
                repository.saveMemo(updated)
                setStatus("업로드 완료")
                clearStatusAfterDelay()
            } catch (e: Exception) {
                setStatus("업로드 실패: ${e.message}")
            }
        }
    }

    /** 이미지 제거 + GitHub 삭제 */
    fun removeImage(memo: Memo, imageUrl: String) {
        viewModelScope.launch {
            val updated = memo.copy(
                images = memo.images.filter { it != imageUrl },
                updated = System.currentTimeMillis()
            )
            repository.saveMemo(updated)
            try {
                val token = getToken()
                gitHubUploader.deleteFile(imageUrl, token)
            } catch (e: Exception) {
                // 삭제 실패해도 UI에서는 이미 제거됨
            }
        }
    }

    /** 파일 제거 + GitHub 삭제 */
    fun removeFile(memo: Memo, fileUrl: String) {
        viewModelScope.launch {
            val updated = memo.copy(
                files = memo.files.filter { (it["url"] ?: "") != fileUrl },
                updated = System.currentTimeMillis()
            )
            repository.saveMemo(updated)
            try {
                val token = getToken()
                gitHubUploader.deleteFile(fileUrl, token)
            } catch (e: Exception) {
                // 삭제 실패해도 UI에서는 이미 제거됨
            }
        }
    }

    private fun updateLocalMemo(updated: Memo) {
        rawMemos = rawMemos.map { if (it.id == updated.id) updated else it }
        _uiState.value = _uiState.value.copy(memos = applySortAndFilter(rawMemos))
        MemoWidgetProvider.updateWidgetsForMemo(getApplication(), updated)
    }

    private fun debounceSave(memo: Memo) {
        saveJob?.cancel()
        setStatus("저장 중...")
        saveJob = viewModelScope.launch {
            delay(1400)
            repository.saveMemo(memo)
            setStatus("저장됨")
            clearStatusAfterDelay()
        }
    }

    private fun setStatus(msg: String) {
        _uiState.value = _uiState.value.copy(statusMessage = msg)
    }

    private fun clearStatusAfterDelay() {
        viewModelScope.launch {
            delay(2200)
            if (_uiState.value.statusMessage == "저장됨" || _uiState.value.statusMessage == "업로드 완료") {
                setStatus("")
            }
        }
    }

    private suspend fun getToken(): String {
        githubToken?.let { return it }
        val token = repository.loadGithubToken()
        githubToken = token
        return token
    }
}
