package com.github.miludeshiji.reelva

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

/** 将视频截图写入 Pictures/Reelva，Android 10 及以上不申请存储权限。 */
class PlayerScreenshotBridge(private val activity: Activity, messenger: BinaryMessenger) {
    companion object {
        private const val REQUEST_WRITE_STORAGE = 1005
    }

    private data class Screenshot(
        val data: ByteArray,
        val name: String,
        val result: MethodChannel.Result
    )

    private val channel = MethodChannel(messenger, "reelva/player_screenshot")
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private var pending: Screenshot? = null

    init {
        channel.setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "save") {
            result.notImplemented()
            return
        }
        if (pending != null) {
            result.error("ALREADY_ACTIVE", "A screenshot is already being saved", null)
            return
        }
        val data = call.argument<ByteArray>("data")
        val name = call.argument<String>("name")
        if (data == null || data.isEmpty() || name.isNullOrBlank() ||
            name.any { it == '/' || it == '\\' || it == '\u0000' }
        ) {
            result.error("INVALID_ARGUMENT", "Invalid screenshot data or filename", null)
            return
        }
        val request = Screenshot(data, name, result)
        pending = request
        try {
            if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.P &&
                activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                activity.requestPermissions(
                    arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                    REQUEST_WRITE_STORAGE
                )
            } else {
                save(request)
            }
        } catch (_: Exception) {
            pending = null
            result.error("SAVE_FAILED", "Unable to save screenshot", null)
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_WRITE_STORAGE) return
        val request = pending ?: return
        if (grantResults.firstOrNull() != PackageManager.PERMISSION_GRANTED) {
            pending = null
            request.result.error("PERMISSION_DENIED", "Storage permission was denied", null)
            return
        }
        save(request)
    }

    private fun save(request: Screenshot) {
        executor.execute {
            val success = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    saveToMediaStore(request)
                } else {
                    saveToLegacyStorage(request)
                }
                true
            } catch (_: Exception) {
                false
            }
            handler.post {
                if (pending === request) {
                    pending = null
                    if (success) request.result.success(null)
                    else request.result.error("SAVE_FAILED", "Unable to save screenshot", null)
                }
            }
        }
    }

    private fun saveToMediaStore(request: Screenshot) {
        val resolver = activity.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, request.name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Reelva")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values)
            ?: throw IOException("Unable to create screenshot")
        try {
            val output = resolver.openOutputStream(uri, "w")
                ?: throw IOException("Unable to open screenshot")
            output.use { it.write(request.data) }
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            if (resolver.update(uri, values, null, null) == 0) {
                throw IOException("Unable to publish screenshot")
            }
        } catch (error: Exception) {
            runCatching { resolver.delete(uri, null, null) }
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun saveToLegacyStorage(request: Screenshot) {
        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
            "Reelva"
        )
        if (!directory.isDirectory && !directory.mkdirs()) {
            throw IOException("Unable to create screenshot directory")
        }
        val file = File(directory, request.name)
        if (!file.createNewFile()) throw IOException("Screenshot already exists")
        try {
            file.outputStream().use { it.write(request.data) }
            MediaScannerConnection.scanFile(
                activity,
                arrayOf(file.absolutePath),
                arrayOf("image/png"),
                null
            )
        } catch (error: Exception) {
            file.delete()
            throw error
        }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pending?.result?.error("CANCELLED", "Screenshot saving was cancelled", null)
        pending = null
        executor.shutdown()
    }
}
