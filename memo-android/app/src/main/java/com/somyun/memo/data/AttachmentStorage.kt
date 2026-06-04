package com.somyun.memo.data

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import java.io.File

data class StoredAttachment(
    val name: String,
    val uri: String,
    val mimeType: String
)

object AttachmentStorage {
    fun copyToInternalStorage(context: Context, sourceUri: Uri): StoredAttachment? {
        val resolver = context.contentResolver
        val mimeType = resolver.getType(sourceUri).orEmpty()
        val displayName = getDisplayName(context, sourceUri)
        val safeName = displayName.replace(Regex("""[^\w가-힣._-]"""), "_")
        val targetDir = File(context.filesDir, "memo_attachments").apply { mkdirs() }
        val target = File(targetDir, "${System.currentTimeMillis()}_$safeName")

        resolver.openInputStream(sourceUri)?.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        } ?: return null

        val contentUri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.fileprovider",
            target
        )
        return StoredAttachment(displayName, contentUri.toString(), mimeType)
    }

    fun readBytes(context: Context, uri: String): ByteArray? =
        context.contentResolver.openInputStream(Uri.parse(uri))?.use { it.readBytes() }

    fun isImage(attachment: StoredAttachment): Boolean =
        attachment.mimeType.startsWith("image/")

    fun isLocalUri(uri: String): Boolean =
        uri.startsWith("content://") && uri.contains(".fileprovider/")

    fun deleteLocalFile(context: Context, uri: String) {
        runCatching {
            val fileName = Uri.parse(uri).lastPathSegment ?: return@runCatching
            File(File(context.filesDir, "memo_attachments"), fileName).delete()
        }
    }

    private fun getDisplayName(context: Context, uri: Uri): String {
        context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) {
                cursor.getString(index)?.takeIf { it.isNotBlank() }?.let { return it }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
            ?: "attachment_${System.currentTimeMillis()}"
    }
}
