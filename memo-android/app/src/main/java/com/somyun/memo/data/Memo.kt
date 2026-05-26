package com.somyun.memo.data

/**
 * 파일 첨부 정보
 */
data class FileAttachment(
    val name: String = "",
    val url: String = ""
)

/**
 * 메모 데이터 모델 — Firestore 문서와 1:1 대응
 */
data class Memo(
    val id: String = "",
    val text: String = "",
    val images: List<String> = emptyList(),
    val files: List<Map<String, String>> = emptyList(),
    val pinned: Boolean = false,
    val created: Long = System.currentTimeMillis(),
    val updated: Long = System.currentTimeMillis()
) {
    /** Firestore에 저장할 Map 변환 */
    fun toMap(): Map<String, Any> = mapOf(
        "id" to id,
        "text" to text,
        "images" to images,
        "files" to files,
        "pinned" to pinned,
        "created" to created,
        "updated" to updated
    )

    /** files를 FileAttachment 리스트로 변환 */
    val fileAttachments: List<FileAttachment>
        get() = files.map { FileAttachment(it["name"] ?: "", it["url"] ?: "") }

    companion object {
        fun fromFirestore(doc: Map<String, Any>, docId: String): Memo {
            @Suppress("UNCHECKED_CAST")
            return Memo(
                id = docId,
                text = doc["text"] as? String ?: "",
                images = (doc["images"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
                files = (doc["files"] as? List<*>)?.filterIsInstance<Map<String, String>>()
                    ?: emptyList(),
                pinned = doc["pinned"] as? Boolean ?: false,
                created = (doc["created"] as? Number)?.toLong() ?: System.currentTimeMillis(),
                updated = (doc["updated"] as? Number)?.toLong() ?: System.currentTimeMillis()
            )
        }
    }
}
