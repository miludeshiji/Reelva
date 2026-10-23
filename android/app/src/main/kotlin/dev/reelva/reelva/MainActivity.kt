package dev.reelva.reelva

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileNotFoundException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "ReelvaMainActivity"
        private const val CHANNEL = "reelva/media_documents"
        private const val REQUEST_CODE_PICK_VIDEO = 1001
    }

    private var channel: MethodChannel? = null
    private var pendingPickerResult: MethodChannel.Result? = null
    private val openDescriptors = HashMap<Int, ParcelFileDescriptor>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor: ExecutorService = Executors.newCachedThreadPool()
    private var lifecycleGeneration: Long = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        lifecycleGeneration++
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                handleMethodCall(call, result)
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        lifecycleGeneration++
        cleanupResources()
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        lifecycleGeneration++
        cleanupResources()
        ioExecutor.shutdown()
        super.onDestroy()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickVideo" -> handlePickVideo(result)
            "openRead" -> handleOpenRead(call, result)
            "close" -> handleClose(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handlePickVideo(result: MethodChannel.Result) {
        if (pendingPickerResult != null) {
            result.error("ALREADY_ACTIVE", "A media picker is already active", null)
            return
        }

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "video/*"
            flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
        }

        pendingPickerResult = result
        try {
            startActivityForResult(intent, REQUEST_CODE_PICK_VIDEO)
        } catch (e: SecurityException) {
            pendingPickerResult = null
            Log.w(TAG, "SecurityException launching document picker")
            result.error("SECURITY_ERROR", "Permission denied launching document picker", null)
        } catch (e: Exception) {
            pendingPickerResult = null
            Log.w(TAG, "Failed to launch document picker")
            result.error("FAILED", "Unable to launch document picker", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CODE_PICK_VIDEO) {
            return
        }

        val callback = pendingPickerResult ?: return
        pendingPickerResult = null

        if (resultCode != Activity.RESULT_OK || data == null || data.data == null) {
            callback.success(null)
            return
        }

        val uri: Uri = data.data!!
        val scheme = uri.scheme?.lowercase()
        if (scheme != "content") {
            callback.error("INVALID_SCHEME", "Only content URI is supported", null)
            return
        }

        val requestGeneration = lifecycleGeneration
        ioExecutor.execute {
            var displayName = "视频"
            try {
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIndex != -1) {
                            val name = cursor.getString(nameIndex)
                            if (!name.isNullOrBlank()) {
                                displayName = name
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to query document display name; fallback to default label")
                displayName = "视频"
            }

            mainHandler.post {
                if (lifecycleGeneration != requestGeneration || isDestroyed || isFinishing) {
                    callback.error("ACTIVITY_DESTROYED", "Activity was destroyed before selection finished", null)
                    return@post
                }
                callback.success(
                    mapOf(
                        "uri" to uri.toString(),
                        "name" to displayName
                    )
                )
            }
        }
    }

    private fun handleOpenRead(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "URI cannot be empty", null)
            return
        }

        val uri = try {
            Uri.parse(uriString)
        } catch (e: Exception) {
            result.error("INVALID_ARGUMENT", "Malformed URI", null)
            return
        }

        val scheme = uri.scheme?.lowercase()
        if (scheme != "content") {
            result.error("INVALID_SCHEME", "Only content URI is supported", null)
            return
        }

        val requestGeneration = lifecycleGeneration
        ioExecutor.execute {
            val pfd: ParcelFileDescriptor?
            try {
                pfd = contentResolver.openFileDescriptor(uri, "r")
            } catch (e: FileNotFoundException) {
                mainHandler.post {
                    if (lifecycleGeneration == requestGeneration && !isDestroyed && !isFinishing) {
                        result.error("FILE_NOT_FOUND", "Document not found or inaccessible", null)
                    }
                }
                return@execute
            } catch (e: SecurityException) {
                mainHandler.post {
                    if (lifecycleGeneration == requestGeneration && !isDestroyed && !isFinishing) {
                        result.error("SECURITY_ERROR", "Permission denied accessing document", null)
                    }
                }
                return@execute
            } catch (e: Exception) {
                mainHandler.post {
                    if (lifecycleGeneration == requestGeneration && !isDestroyed && !isFinishing) {
                        result.error("IO_ERROR", "Failed to open document descriptor", null)
                    }
                }
                return@execute
            }

            if (pfd == null) {
                mainHandler.post {
                    if (lifecycleGeneration == requestGeneration && !isDestroyed && !isFinishing) {
                        result.error("FILE_NOT_FOUND", "Unable to open document descriptor", null)
                    }
                }
                return@execute
            }

            mainHandler.post {
                if (lifecycleGeneration != requestGeneration || isDestroyed || isFinishing) {
                    try {
                        pfd.close()
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to close orphaned descriptor after lifecycle invalidation")
                    }
                    result.error("ACTIVITY_DESTROYED", "Activity or engine was detached before descriptor was registered", null)
                    return@post
                }

                val fd = pfd.fd
                openDescriptors[fd] = pfd
                result.success(fd)
            }
        }
    }

    private fun handleClose(call: MethodCall, result: MethodChannel.Result) {
        val fd = call.argument<Number>("descriptor")?.toInt()
        if (fd != null) {
            val pfd = openDescriptors.remove(fd)
            if (pfd != null) {
                try {
                    pfd.close()
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to close media document descriptor")
                    result.error("CLOSE_FAILED", "Failed to close media document descriptor", null)
                    return
                }
            }
        }
        result.success(null)
    }

    private fun cleanupResources() {
        pendingPickerResult?.let { pending ->
            pendingPickerResult = null
            pending.error("ACTIVITY_DESTROYED", "Activity was destroyed before selection finished", null)
        }

        val descriptors = openDescriptors.values.toList()
        openDescriptors.clear()
        for (pfd in descriptors) {
            try {
                pfd.close()
            } catch (e: Exception) {
                Log.w(TAG, "Failed to close open descriptor during cleanup")
            }
        }
    }
}
