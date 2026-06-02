package com.somyun.memo.data

import android.content.Context
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.Source
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await

/**
 * Firestore memos 컬렉션과 통신하는 Repository
 */
class MemoRepository(private val context: Context) {
    private val db = FirebaseFirestore.getInstance()
    private val memosRef = db.collection("memos")
    private val configRef = db.collection("config")

    /** 메모 변경 시 호출되는 콜백 (위젯 갱신 등 외부 연동용) */
    var onMemoChanged: ((memoId: String?) -> Unit)? = null

    /**
     * 실시간 메모 스트림 — onSnapshot과 동일
     */
    fun observeMemos(): Flow<List<Memo>> = callbackFlow {
        val listener: ListenerRegistration = memosRef.addSnapshotListener { snapshot, error ->
            if (error != null) {
                close(error)
                return@addSnapshotListener
            }
            val memos = snapshot?.documents?.mapNotNull { doc ->
                doc.data?.let { Memo.fromFirestore(it, doc.id) }
            } ?: emptyList()
            trySend(memos)
        }
        awaitClose { listener.remove() }
    }

    /** 단일 메모 조회 (위젯 등에서 사용) */
    suspend fun getMemo(memoId: String): Memo? {
        val doc = memosRef.document(memoId).get().await()
        return doc.data?.let { Memo.fromFirestore(it, doc.id) }
    }

    suspend fun getMemo(memoId: String, source: Source): Memo? {
        val doc = memosRef.document(memoId).get(source).await()
        return doc.data?.let { Memo.fromFirestore(it, doc.id) }
    }

    /** 메모 저장 (생성 및 수정) */
    suspend fun saveMemo(memo: Memo) {
        memosRef.document(memo.id).set(memo.toMap()).await()
        onMemoChanged?.invoke(memo.id)
    }

    /** 메모 삭제 */
    suspend fun deleteMemo(memoId: String) {
        memosRef.document(memoId).delete().await()
        onMemoChanged?.invoke(null)
    }

    /** GitHub 토큰 로드 */
    suspend fun loadGithubToken(): String {
        val doc = configRef.document("github").get().await()
        return doc.getString("token") ?: throw Exception("GitHub 토큰 없음")
    }
}
