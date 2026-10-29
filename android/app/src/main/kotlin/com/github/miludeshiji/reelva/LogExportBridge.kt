package com.github.miludeshiji.reelva

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** 使用系统文档选择器导出，不申请共享存储权限。 */
class LogExportBridge(private val activity: Activity, messenger: BinaryMessenger) {
    companion object {
        private const val REQUEST_CREATE_LOG = 1004
    }

    private data class Export(val data: ByteArray, val result: MethodChannel.Result)

    private val channel = MethodChannel(messenger, "reelva/log_export")
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private var pending: Export? = null

    init {
        channel.setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "save") {
            result.notImplemented()
            return
        }
        if (pending != null) {
            result.error("ALREADY_ACTIVE", "A log export is already active", null)
            return
        }
        val data = call.argument<ByteArray>("data")
        val name = call.argument<String>("name")
        if (data == null || name.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Missing log data or filename", null)
            return
        }
        pending = Export(data, result)
        try {
            activity.startActivityForResult(
                Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TITLE, name)
                },
                REQUEST_CREATE_LOG
            )
        } catch (_: Exception) {
            pending = null
            result.error("EXPORT_FAILED", "Unable to open document picker", null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CREATE_LOG) return false
        val request = pending ?: return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            request.result.success(false)
            return true
        }
        executor.execute {
            val success = try {
                val output = activity.contentResolver.openOutputStream(uri, "wt")
                    ?: throw java.io.IOException("Unable to open destination")
                output.use { it.write(request.data) }
                true
            } catch (_: Exception) {
                false
            }
            handler.post {
                if (pending === request) {
                    pending = null
                    if (success) request.result.success(true)
                    else request.result.error("EXPORT_FAILED", "Unable to save log file", null)
                }
            }
        }
        return true
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pending?.result?.success(false)
        pending = null
        executor.shutdown()
    }
}
