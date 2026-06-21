package com.jbrains.mova

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.media.MediaMetadataRetriever
import android.graphics.Bitmap
import android.provider.MediaStore.Video.Media
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import java.security.KeyStore

class MainActivity : FlutterActivity() {
    private val fileChannelName = "mova/native_files"
    private val storageChannelName = "mova/storage"
    private val mediaChannelName = "mova/media"
    private val videoFramesChannelName = "mova/video_frames"
    private val videoCompositionChannelName = "mova/video_composition"
    private val preferencesName = "mova_preferences"
    private val appStateKey = "app_state_json"
    private val databaseName = "mova.db"
    private val databaseVersion = 1
    private val tableName = "app_kv_store"
    private val columnKey = "store_key"
    private val columnValue = "store_value"
    private val stateStoreKey = "encrypted_app_state"
    private val keyStoreAlias = "mova_state_key"
    private val pickMediaRequestCode = 2048
    private val exportBackupRequestCode = 2049
    private val importBackupRequestCode = 2050
    private val pickPhotoPickerRequestCode = 2051
    private val pickVideoPickerRequestCode = 2052
    private val pickAudioPickerRequestCode = 2053

    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingExportResult: MethodChannel.Result? = null
    private var pendingImportResult: MethodChannel.Result? = null
    private var pendingExportPayload: String? = null
    private lateinit var databaseHelper: AppDatabaseHelper

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        databaseHelper = AppDatabaseHelper(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fileChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickMediaFiles" -> pickMediaFiles(result)
                "pickSingleVideoFile" -> pickSingleVideoFile(result)
                "pickSingleAudioFile" -> pickSingleAudioFile(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, videoFramesChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "captureFrame" -> {
                    val source = call.argument<String>("source")
                    val positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L
                    val suggestedFileName = call.argument<String>("suggestedFileName")
                    if (source.isNullOrBlank()) {
                        result.error("capture_failed", "缺少视频来源。", null)
                    } else {
                        try {
                            result.success(captureVideoFrame(source, positionMs, suggestedFileName))
                        } catch (error: Exception) {
                            result.error("capture_failed", error.message ?: "截帧失败。", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, storageChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "readState" -> {
                    try {
                        result.success(readState())
                    } catch (error: Exception) {
                        result.error("read_failed", error.message ?: "读取状态失败。", null)
                    }
                }
                "writeState" -> {
                    val value = call.argument<String>("value") ?: ""
                    try {
                        writeState(value)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("write_failed", error.message ?: "写入状态失败。", null)
                    }
                }
                "exportState" -> {
                    val value = call.argument<String>("value") ?: ""
                    val suggestedFileName = call.argument<String>("suggestedFileName") ?: "mova-backup.json"
                    exportState(result, value, suggestedFileName)
                }
                "importState" -> importState(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveVideoToGallery" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName")
                    if (sourcePath.isNullOrBlank()) {
                        result.error("save_failed", "缺少 sourcePath。", null)
                    } else {
                        try {
                            result.success(saveVideoToGallery(sourcePath, fileName))
                        } catch (error: Exception) {
                            result.error("save_failed", error.message ?: "保存视频失败。", null)
                        }
                    }
                }
                "saveImageToGallery" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName")
                    val mimeType = call.argument<String>("mimeType")
                    if (sourcePath.isNullOrBlank()) {
                        result.error("save_failed", "缺少 sourcePath。", null)
                    } else {
                        try {
                            result.success(saveImageToGallery(sourcePath, fileName, mimeType))
                        } catch (error: Exception) {
                            result.error("save_failed", error.message ?: "保存图片失败。", null)
                        }
                    }
                }
                "openMedia" -> {
                    val uri = call.argument<String>("uri")
                    val mimeType = call.argument<String>("mimeType")
                    if (uri.isNullOrBlank()) {
                        result.error("open_failed", "缺少媒体地址。", null)
                    } else {
                        try {
                            openMedia(uri, mimeType)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("open_failed", error.message ?: "打开媒体失败。", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, videoCompositionChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "exportComposition" -> exportComposition(call.arguments, result)
                "cancelComposition" -> result.success(true)
                else -> result.notImplemented()
            }
        }
    }

    private fun exportComposition(arguments: Any?, result: MethodChannel.Result) {
        try {
            val map = arguments as? Map<*, *> ?: throw IllegalArgumentException("缺少合成参数。")
            val outputPath = map["outputPath"] as? String ?: throw IllegalArgumentException("缺少输出路径。")
            val clips = map["clips"] as? List<*> ?: emptyList<Any>()
            if (clips.isEmpty()) {
                throw IllegalArgumentException("至少添加 1 个视频片段。")
            }
            if (clips.size > 1) {
                result.error("export_unsupported", "多视频合成引擎正在修复中，当前版本不会再闪退。请先使用单视频导出。", null)
                return
            }
            val clip = clips.first() as? Map<*, *> ?: throw IllegalArgumentException("片段参数无效。")
            val localUri = clip["localUri"] as? String ?: throw IllegalArgumentException("缺少视频文件。")
            val startMs = (clip["startMs"] as? Number)?.toLong() ?: 0L
            val sourcePath = localPathFromUri(localUri)
            if (startMs != 0L) {
                result.error("export_unsupported", "裁剪导出引擎正在修复中，当前版本不会再闪退。请先使用完整单视频导出。", null)
                return
            }
            val sourceFile = File(sourcePath)
            if (!sourceFile.exists()) {
                throw IllegalArgumentException("视频文件不存在。")
            }
            val outputFile = File(outputPath)
            outputFile.parentFile?.mkdirs()
            FileInputStream(sourceFile).use { input ->
                FileOutputStream(outputFile).use { output -> input.copyTo(output) }
            }
            result.success(
                mapOf(
                    "localPath" to outputFile.absolutePath,
                    "fileName" to outputFile.name,
                    "durationMs" to ((clip["endMs"] as? Number)?.toInt() ?: 0),
                    "width" to 0,
                    "height" to 0,
                )
            )
        } catch (error: Exception) {
            result.error("export_failed", error.message ?: "视频导出失败。", null)
        }
    }

    private fun localPathFromUri(value: String): String {
        if (value.startsWith("file://")) {
            return Uri.parse(value).path ?: value.removePrefix("file://")
        }
        return value
    }

    private fun readState(): String? {
        val stored = databaseHelper.getValue(stateStoreKey)
        if (!stored.isNullOrBlank()) {
            return decryptString(stored)
        }

        val preferences = getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
        val legacy = preferences.getString(appStateKey, null)
        if (!legacy.isNullOrBlank()) {
            writeState(legacy)
            preferences.edit().remove(appStateKey).apply()
        }
        return legacy
    }

    private fun writeState(value: String) {
        val encrypted = encryptString(value)
        databaseHelper.putValue(stateStoreKey, encrypted)
    }

    private fun exportState(result: MethodChannel.Result, value: String, suggestedFileName: String) {
        if (pendingExportResult != null) {
            result.error("export_busy", "导出窗口正在打开。", null)
            return
        }
        pendingExportResult = result
        pendingExportPayload = value
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, suggestedFileName)
        }
        startActivityForResult(intent, exportBackupRequestCode)
    }

    private fun importState(result: MethodChannel.Result) {
        if (pendingImportResult != null) {
            result.error("import_busy", "导入窗口正在打开。", null)
            return
        }
        pendingImportResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
        }
        startActivityForResult(intent, importBackupRequestCode)
    }

    private fun pickMediaFiles(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("picker_busy", "文件选择器正在打开。", null)
            return
        }

        pendingPickResult = result
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val intent = Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, 20)
            }
            startActivityForResult(intent, pickPhotoPickerRequestCode)
            return
        }
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*", "audio/*"))
        }
        startActivityForResult(Intent.createChooser(intent, "选择素材"), pickMediaRequestCode)
    }

    private fun pickSingleVideoFile(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("picker_busy", "文件选择器正在打开。", null)
            return
        }
        pendingPickResult = result
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val intent = Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "video/*"
            }
            startActivityForResult(intent, pickVideoPickerRequestCode)
            return
        }
        val intent = Intent(
            Intent.ACTION_PICK,
            Media.EXTERNAL_CONTENT_URI
        ).apply {
            type = "video/*"
        }
        startActivityForResult(Intent.createChooser(intent, "选择视频"), pickVideoPickerRequestCode)
    }

    private fun pickSingleAudioFile(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("picker_busy", "文件选择器正在打开。", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
        }
        startActivityForResult(Intent.createChooser(intent, "选择音频"), pickAudioPickerRequestCode)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            pickMediaRequestCode -> handlePickMediaResult(resultCode, data)
            pickPhotoPickerRequestCode -> handlePickMediaResult(resultCode, data)
            pickVideoPickerRequestCode -> handlePickSingleVideoResult(resultCode, data)
            pickAudioPickerRequestCode -> handlePickSingleAudioResult(resultCode, data)
            exportBackupRequestCode -> handleExportResult(resultCode, data)
            importBackupRequestCode -> handleImportResult(resultCode, data)
        }
    }

    private fun handlePickSingleVideoResult(resultCode: Int, data: Intent?) {
        val result = pendingPickResult ?: return
        pendingPickResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }

        val uri = data.data ?: run {
            result.success(null)
            return
        }

        try {
            val mimeType = contentResolver.getType(uri) ?: "video/mp4"
            val localCopy = copyUriToCache(uri, displayName(uri))
            val durationMs = videoDurationMs(localCopy.absolutePath)
            result.success(
                mapOf(
                    "name" to displayName(uri),
                    "mimeType" to mimeType,
                    "uri" to Uri.fromFile(localCopy).toString(),
                    "path" to localCopy.absolutePath,
                    "durationMs" to durationMs,
                )
            )
        } catch (error: Exception) {
            result.error("pick_failed", error.message ?: "读取视频失败。", null)
        }
    }

    private fun handlePickSingleAudioResult(resultCode: Int, data: Intent?) {
        val result = pendingPickResult ?: return
        pendingPickResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }

        val uri = data.data ?: run {
            result.success(null)
            return
        }

        try {
            val mimeType = contentResolver.getType(uri) ?: "audio/mpeg"
            val localCopy = copyUriToCache(uri, displayName(uri))
            result.success(
                mapOf(
                    "name" to displayName(uri),
                    "mimeType" to mimeType,
                    "uri" to Uri.fromFile(localCopy).toString(),
                    "path" to localCopy.absolutePath,
                )
            )
        } catch (error: Exception) {
            result.error("pick_failed", error.message ?: "读取音频失败。", null)
        }
    }

    private fun handlePickMediaResult(resultCode: Int, data: Intent?) {
        val result = pendingPickResult ?: return

        if (resultCode != Activity.RESULT_OK || data == null) {
            pendingPickResult = null
            result.success(emptyList<Map<String, Any>>())
            return
        }

        try {
            val uris = mutableListOf<Uri>()
            val clipData = data.clipData
            if (clipData != null) {
                for (index in 0 until clipData.itemCount) {
                    uris.add(clipData.getItemAt(index).uri)
                }
            } else {
                data.data?.let { uris.add(it) }
            }
            handlePickedUris(uris)
        } catch (error: Exception) {
            pendingPickResult = null
            result.error("pick_failed", error.message ?: "读取文件失败。", null)
        }
    }

    private fun handlePickedUris(uris: List<Uri>) {
        val result = pendingPickResult ?: return
        pendingPickResult = null
        if (uris.isEmpty()) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        try {
            val files = uris.map { uri ->
                val name = displayName(uri)
                val localCopy = copyUriToCache(uri, name)
                mapOf(
                    "name" to name,
                    "mimeType" to (contentResolver.getType(uri) ?: "application/octet-stream"),
                    "bytes" to localCopy.readBytes(),
                    "uri" to Uri.fromFile(localCopy).toString(),
                    "path" to localCopy.absolutePath,
                )
            }
            result.success(files)
        } catch (error: Exception) {
            result.error("pick_failed", error.message ?: "读取文件失败。", null)
        }
    }

    private fun videoDurationMs(path: String): Long {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 15000L
        } finally {
            retriever.release()
        }
    }

    private fun copyUriToCache(uri: Uri, fileName: String): File {
        val safeName = fileName.ifBlank { "video-${System.currentTimeMillis()}.mp4" }
        val target = File(cacheDir, safeName)
        contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(target).use { output -> input.copyTo(output) }
        } ?: throw IllegalStateException("无法读取视频文件。")
        return target
    }

    private fun captureVideoFrame(source: String, positionMs: Long, suggestedFileName: String?): Map<String, Any> {
        val retriever = MediaMetadataRetriever()
        try {
            when {
                source.startsWith("content://") -> retriever.setDataSource(this, Uri.parse(source))
                source.startsWith("file://") -> retriever.setDataSource(Uri.parse(source).path)
                source.startsWith("/") -> retriever.setDataSource(source)
                else -> retriever.setDataSource(source, HashMap())
            }
            val targetTimeUs = positionMs * 1000L
            val bitmap =
                retriever.getFrameAtTime(
                    targetTimeUs,
                    MediaMetadataRetriever.OPTION_CLOSEST
                )
                    ?: retriever.getFrameAtTime(
                        targetTimeUs,
                        MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                    )
                    ?: throw IllegalStateException("无法获取对应时间点的画面。")
            val fileName = (suggestedFileName ?: "frame-${System.currentTimeMillis()}.jpg")
                .replace(Regex("[^A-Za-z0-9._-]"), "_")
            val output = File(cacheDir, fileName)
            FileOutputStream(output).use { stream ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 92, stream)
            }
            return mapOf(
                "path" to output.absolutePath,
                "uri" to Uri.fromFile(output).toString(),
                "width" to bitmap.width,
                "height" to bitmap.height,
                "positionMs" to positionMs,
            )
        } finally {
            retriever.release()
        }
    }

    private fun handleExportResult(resultCode: Int, data: Intent?) {
        val result = pendingExportResult ?: return
        pendingExportResult = null
        val payload = pendingExportPayload
        pendingExportPayload = null

        if (resultCode != Activity.RESULT_OK || data?.data == null || payload == null) {
            result.success(null)
            return
        }

        try {
            contentResolver.openOutputStream(data.data!!)?.use { output ->
                output.write(payload.toByteArray(Charsets.UTF_8))
            } ?: throw IllegalStateException("无法写入备份文件。")
            result.success(data.data!!.toString())
        } catch (error: Exception) {
            result.error("export_failed", error.message ?: "导出备份失败。", null)
        }
    }

    private fun handleImportResult(resultCode: Int, data: Intent?) {
        val result = pendingImportResult ?: return
        pendingImportResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }

        try {
            val content = contentResolver.openInputStream(data.data!!)?.bufferedReader(Charsets.UTF_8)?.use {
                it.readText()
            } ?: throw IllegalStateException("无法读取备份文件。")
            result.success(content)
        } catch (error: Exception) {
            result.error("import_failed", error.message ?: "导入备份失败。", null)
        }
    }

    private fun displayName(uri: Uri): String {
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(uri, null, null, null, null)
            val nameIndex = cursor?.getColumnIndex(OpenableColumns.DISPLAY_NAME) ?: -1
            if (cursor != null && cursor.moveToFirst() && nameIndex >= 0) {
                cursor.getString(nameIndex)
            } else {
                uri.lastPathSegment ?: "asset"
            }
        } finally {
            cursor?.close()
        }
    }

    private fun readBytes(uri: Uri): ByteArray {
        val stream = contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("无法打开文件流。")
        return stream.use { it.readBytes() }
    }

    private fun saveVideoToGallery(sourcePath: String, fileName: String?): Map<String, String> {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) {
            throw IllegalStateException("源视频不存在。")
        }
        val safeFileName = (fileName ?: sourceFile.name).ifBlank { sourceFile.name }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, safeFileName)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/Mova")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                values
            ) ?: throw IllegalStateException("无法创建媒体库条目。")
            contentResolver.openOutputStream(uri)?.use { output ->
                FileInputStream(sourceFile).use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("无法写入媒体库。")
            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            mapOf("path" to safeFileName, "uri" to uri.toString())
        } else {
            val targetDir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
                "Mova"
            )
            if (!targetDir.exists()) {
                targetDir.mkdirs()
            }
            val targetFile = File(targetDir, safeFileName)
            FileInputStream(sourceFile).use { input ->
                FileOutputStream(targetFile).use { output -> input.copyTo(output) }
            }
            sendBroadcast(
                Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE).apply {
                    data = Uri.fromFile(targetFile)
                }
            )
            mapOf("path" to targetFile.absolutePath, "uri" to Uri.fromFile(targetFile).toString())
        }
    }

    private fun saveImageToGallery(
        sourcePath: String,
        fileName: String?,
        mimeType: String?
    ): Map<String, String> {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) {
            throw IllegalStateException("源图片不存在。")
        }
        val safeFileName = (fileName ?: sourceFile.name).ifBlank { sourceFile.name }
        val resolvedMimeType = when {
            !mimeType.isNullOrBlank() -> mimeType
            safeFileName.lowercase().endsWith(".png") -> "image/png"
            safeFileName.lowercase().endsWith(".webp") -> "image/webp"
            else -> "image/jpeg"
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, safeFileName)
                put(MediaStore.Images.Media.MIME_TYPE, resolvedMimeType)
                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Mova")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                values
            ) ?: throw IllegalStateException("无法创建媒体库条目。")
            contentResolver.openOutputStream(uri)?.use { output ->
                FileInputStream(sourceFile).use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("无法写入媒体库。")
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            mapOf("path" to safeFileName, "uri" to uri.toString())
        } else {
            val targetDir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                "Mova"
            )
            if (!targetDir.exists()) {
                targetDir.mkdirs()
            }
            val targetFile = File(targetDir, safeFileName)
            FileInputStream(sourceFile).use { input ->
                FileOutputStream(targetFile).use { output -> input.copyTo(output) }
            }
            sendBroadcast(
                Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE).apply {
                    data = Uri.fromFile(targetFile)
                }
            )
            mapOf("path" to targetFile.absolutePath, "uri" to Uri.fromFile(targetFile).toString())
        }
    }

    private fun openMedia(rawUri: String, mimeType: String?) {
        val uri = when {
            rawUri.startsWith("content://") || rawUri.startsWith("file://") -> Uri.parse(rawUri)
            rawUri.startsWith("/") -> {
                val file = File(rawUri)
                FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
            }
            else -> Uri.parse(rawUri)
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType ?: "*/*")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, "打开媒体"))
    }

    private fun encryptString(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey())
        val iv = cipher.iv
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val ivBase64 = Base64.encodeToString(iv, Base64.NO_WRAP)
        val encryptedBase64 = Base64.encodeToString(encrypted, Base64.NO_WRAP)
        return "$ivBase64:$encryptedBase64"
    }

    private fun decryptString(value: String): String {
        if (!value.contains(":")) {
            return value
        }
        val parts = value.split(":", limit = 2)
        if (parts.size != 2) {
            return value
        }
        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val encrypted = Base64.decode(parts[1], Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            getOrCreateSecretKey(),
            GCMParameterSpec(128, iv),
        )
        val decrypted = cipher.doFinal(encrypted)
        return String(decrypted, Charsets.UTF_8)
    }

    private fun getOrCreateSecretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(keyStoreAlias, null)
        if (existing is SecretKey) {
            return existing
        }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore"
        )
        val spec = KeyGenParameterSpec.Builder(
            keyStoreAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build()
        keyGenerator.init(spec)
        return keyGenerator.generateKey()
    }

    private inner class AppDatabaseHelper(context: Context) :
        SQLiteOpenHelper(context, databaseName, null, databaseVersion) {

        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS $tableName (
                    $columnKey TEXT PRIMARY KEY,
                    $columnValue TEXT NOT NULL
                )
                """.trimIndent()
            )
        }

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            // No-op for v1.
        }

        fun getValue(key: String): String? {
            readableDatabase.query(
                tableName,
                arrayOf(columnValue),
                "$columnKey = ?",
                arrayOf(key),
                null,
                null,
                null,
                "1"
            ).use { cursor ->
                if (cursor.moveToFirst()) {
                    return cursor.getString(0)
                }
            }
            return null
        }

        fun putValue(key: String, value: String) {
            val contentValues = ContentValues().apply {
                put(columnKey, key)
                put(columnValue, value)
            }
            writableDatabase.insertWithOnConflict(
                tableName,
                null,
                contentValues,
                SQLiteDatabase.CONFLICT_REPLACE
            )
        }
    }
}
