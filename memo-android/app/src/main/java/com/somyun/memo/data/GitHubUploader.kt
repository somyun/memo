package com.somyun.memo.data

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.Base64
import java.util.concurrent.TimeUnit

/**
 * GitHub API를 통한 이미지/파일 업로드 및 삭제
 */
class GitHubUploader {
    companion object {
        private const val OWNER = "somyun"
        private const val REPO = "memo"
        private const val BRANCH = "main"
        private const val MAX_DIMENSION = 1600
        private const val JPEG_QUALITY = 82
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    /**
     * 이미지 바이트를 압축하여 GitHub에 업로드
     * @return CDN URL
     */
    suspend fun uploadImage(imageBytes: ByteArray, token: String): String = withContext(Dispatchers.IO) {
        // 1) 압축
        val compressed = compressImage(imageBytes)
        val base64 = Base64.getEncoder().encodeToString(compressed)

        // 2) 파일명 생성
        val fileName = "uploads/${System.currentTimeMillis()}_${(Math.random() * 100000).toLong()}.jpg"

        // 3) GitHub API 호출
        uploadToGitHub(fileName, base64, "Upload image $fileName", token)

        // 4) CDN URL 반환 (이미지용 jsDelivr)
        "https://cdn.jsdelivr.net/gh/$OWNER/$REPO@$BRANCH/$fileName"
    }

    /**
     * 일반 파일을 GitHub에 업로드
     * @return raw.githubusercontent URL
     */
    suspend fun uploadFile(fileBytes: ByteArray, originalName: String, token: String): String =
        withContext(Dispatchers.IO) {
            val base64 = Base64.getEncoder().encodeToString(fileBytes)
            val safeName = originalName.replace(Regex("[^a-zA-Z0-9가-힣._-]"), "_")
            val fileName = "uploads/${System.currentTimeMillis()}_$safeName"

            uploadToGitHub(fileName, base64, "Upload file $fileName", token)

            "https://raw.githubusercontent.com/$OWNER/$REPO/$BRANCH/$fileName"
        }

    /**
     * GitHub에서 파일 삭제 (SHA 조회 → DELETE)
     */
    suspend fun deleteFile(fileUrl: String, token: String) = withContext(Dispatchers.IO) {
        val filePath = extractPath(fileUrl) ?: return@withContext
        val apiUrl = "https://api.github.com/repos/$OWNER/$REPO/contents/$filePath?ref=$BRANCH"

        // 1) SHA 조회
        val infoReq = Request.Builder()
            .url(apiUrl)
            .header("Authorization", "token $token")
            .header("Accept", "application/vnd.github+json")
            .build()

        val infoRes = client.newCall(infoReq).execute()
        if (!infoRes.isSuccessful) return@withContext

        val sha = JSONObject(infoRes.body?.string() ?: "").getString("sha")

        // 2) 삭제
        val deleteBody = JSONObject().apply {
            put("message", "Delete $filePath")
            put("sha", sha)
            put("branch", BRANCH)
        }.toString().toRequestBody("application/json".toMediaType())

        val delReq = Request.Builder()
            .url("https://api.github.com/repos/$OWNER/$REPO/contents/$filePath")
            .delete(deleteBody)
            .header("Authorization", "token $token")
            .header("Accept", "application/vnd.github+json")
            .build()

        client.newCall(delReq).execute()
    }

    private fun uploadToGitHub(fileName: String, base64Content: String, message: String, token: String) {
        val body = JSONObject().apply {
            put("message", message)
            put("content", base64Content)
            put("branch", BRANCH)
        }.toString().toRequestBody("application/json".toMediaType())

        val request = Request.Builder()
            .url("https://api.github.com/repos/$OWNER/$REPO/contents/$fileName")
            .put(body)
            .header("Authorization", "token $token")
            .header("Accept", "application/vnd.github+json")
            .build()

        val response = client.newCall(request).execute()
        if (!response.isSuccessful) {
            throw Exception("GitHub 업로드 실패: ${response.code}")
        }
    }

    private fun compressImage(imageBytes: ByteArray): ByteArray {
        if (imageBytes.size < 500 * 1024) return imageBytes

        val original = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size) ?: return imageBytes

        var w = original.width
        var h = original.height

        if (w > MAX_DIMENSION || h > MAX_DIMENSION) {
            if (w > h) {
                h = (h * MAX_DIMENSION.toFloat() / w).toInt()
                w = MAX_DIMENSION
            } else {
                w = (w * MAX_DIMENSION.toFloat() / h).toInt()
                h = MAX_DIMENSION
            }
        }

        val scaled = Bitmap.createScaledBitmap(original, w, h, true)
        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)

        // 압축 후 더 커지면 원본 사용
        return if (out.size() >= imageBytes.size) imageBytes else out.toByteArray()
    }

    private fun extractPath(url: String): String? {
        // jsDelivr
        Regex("/gh/[^/]+/[^@]+@[^/]+/(.+)$").find(url)?.let { return it.groupValues[1] }
        // raw.githubusercontent
        Regex("raw\\.githubusercontent\\.com/[^/]+/[^/]+/[^/]+/(.+)$").find(url)?.let { return it.groupValues[1] }
        return null
    }
}
