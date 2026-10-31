package com.github.miludeshiji.reelva

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "ReelvaMainActivity"
        private const val CHANNEL = "reelva/media_documents"
        private const val REQUEST_CODE_PICK_VIDEO = 1001
        private const val REQUEST_CODE_PICK_DIRECTORY = 1002
    }

    private var channel: MethodChannel? = null
    private var appUpdateBridge: AppUpdateBridge? = null
    private var logExportBridge: LogExportBridge? = null
    private var playerScreenshotBridge: PlayerScreenshotBridge? = null
    private var openListBridge: OpenListBridge? = null
    private var brightnessChannel: MethodChannel? = null
    private var brightnessBeforePlayback: Float? = null
    private var pendingPickerResult: MethodChannel.Result? = null
    private var pendingDirectoryPickerResult: MethodChannel.Result? = null
    private val openDescriptors = HashMap<Int, ParcelFileDescriptor>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor: ExecutorService = Executors.newCachedThreadPool()
    private var lifecycleGeneration: Long = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        appUpdateBridge = AppUpdateBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        logExportBridge = LogExportBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        playerScreenshotBridge = PlayerScreenshotBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        openListBridge = OpenListBridge(flutterEngine.dartExecutor.binaryMessenger)
        lifecycleGeneration++
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                handleMethodCall(call, result)
            }
        }
        brightnessChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "reelva/screen_brightness"
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "get" -> {
                        val brightness = window.attributes.screenBrightness
                        val current = if (brightness >= 0) brightness.toDouble() else
                            Settings.System.getInt(
                                contentResolver, Settings.System.SCREEN_BRIGHTNESS, 127
                            ) / 255.0
                        result.success(current.coerceIn(0.0, 1.0))
                    }
                    "set" -> {
                        val value = call.argument<Number>("brightness")?.toDouble()
                        if (value == null || !value.isFinite() || value !in 0.0..1.0) {
                            result.error("INVALID_ARGUMENT", "Invalid screen brightness", null)
                        } else {
                            val attributes = window.attributes
                            if (brightnessBeforePlayback == null) {
                                brightnessBeforePlayback = attributes.screenBrightness
                            }
                            attributes.screenBrightness = value.toFloat()
                            window.attributes = attributes
                            result.success(null)
                        }
                    }
                    "reset" -> {
                        resetScreenBrightness()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        appUpdateBridge?.close()
        appUpdateBridge = null
        logExportBridge?.close()
        logExportBridge = null
        playerScreenshotBridge?.close()
        playerScreenshotBridge = null
        openListBridge?.close()
        openListBridge = null
        lifecycleGeneration++
        cleanupResources()
        channel?.setMethodCallHandler(null)
        channel = null
        resetScreenBrightness()
        brightnessChannel?.setMethodCallHandler(null)
        brightnessChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        lifecycleGeneration++
        cleanupResources()
        resetScreenBrightness()
        ioExecutor.shutdown()
        super.onDestroy()
    }

    private fun resetScreenBrightness() {
        val previous = brightnessBeforePlayback ?: return
        val attributes = window.attributes
        attributes.screenBrightness = previous
        window.attributes = attributes
        brightnessBeforePlayback = null
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickVideo" -> handlePickDocument(result, "video/*")
            "pickSubtitle" -> handlePickDocument(result, "*/*")
            "pickDanmaku" -> handlePickDocument(result, "*/*")
            "readDocument" -> handleReadDocument(call, result)
            "openRead" -> handleOpenRead(call, result)
            "close" -> handleClose(call, result)
            "pickDirectory" -> handlePickDirectory(call, result)
            "listChildren" -> handleListChildren(call, result)
            "statDocument" -> handleStatDocument(call, result)
            "checkPermission" -> handleCheckPermission(call, result)
            "parentDocument" -> handleParentDocument(call, result)
            "readSidecar" -> handleSidecar(call, result, false)
            "writeSidecar" -> handleSidecar(call, result, true)
            else -> result.notImplemented()
        }
    }

    private fun handlePickDocument(result: MethodChannel.Result, mimeType: String) {
        if (pendingPickerResult != null || pendingDirectoryPickerResult != null) {
            result.error("ALREADY_ACTIVE", "A media picker is already active", null)
            return
        }

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
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

    private fun handlePickDirectory(call: MethodCall, result: MethodChannel.Result) {
        if (pendingPickerResult != null || pendingDirectoryPickerResult != null) {
            result.error("ALREADY_ACTIVE", "A media picker is already active", null)
            return
        }

        val initialLocator = call.argument<String>("initialLocator")
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            if (!initialLocator.isNullOrBlank()) {
                try {
                    val initialUri = Uri.parse(initialLocator)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        putExtra(DocumentsContract.EXTRA_INITIAL_URI, initialUri)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to parse initialLocator for document tree picker")
                }
            }
        }

        pendingDirectoryPickerResult = result
        try {
            startActivityForResult(intent, REQUEST_CODE_PICK_DIRECTORY)
        } catch (e: SecurityException) {
            pendingDirectoryPickerResult = null
            Log.w(TAG, "SecurityException launching document tree picker")
            result.error("SECURITY_ERROR", "Permission denied launching document tree picker", null)
        } catch (e: Exception) {
            pendingDirectoryPickerResult = null
            Log.w(TAG, "Failed to launch document tree picker")
            result.error("FAILED", "Unable to launch document tree picker", null)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        playerScreenshotBridge?.onRequestPermissionsResult(requestCode, grantResults)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (appUpdateBridge?.onActivityResult(requestCode) == true) return
        if (logExportBridge?.onActivityResult(requestCode, resultCode, data) == true) return
        if (requestCode == REQUEST_CODE_PICK_DIRECTORY) {
            handleDirectoryPickerResult(resultCode, data)
            return
        }

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

    private fun handleDirectoryPickerResult(resultCode: Int, data: Intent?) {
        val callback = pendingDirectoryPickerResult ?: return
        pendingDirectoryPickerResult = null

        if (resultCode != Activity.RESULT_OK || data == null || data.data == null) {
            callback.success(null)
            return
        }

        val treeUri: Uri = data.data!!
        val scheme = treeUri.scheme?.lowercase()
        if (scheme != "content") {
            callback.error("INVALID_SCHEME", "Only content URI is supported", null)
            return
        }

        val takeFlags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        if ((takeFlags and Intent.FLAG_GRANT_READ_URI_PERMISSION) == 0) {
            callback.error("SECURITY_ERROR", "Read permission not granted for directory", null)
            return
        }

        try {
            contentResolver.takePersistableUriPermission(treeUri, takeFlags)
        } catch (e: SecurityException) {
            Log.w(TAG, "Failed to persist read permission for directory")
            callback.error("SECURITY_ERROR", "Failed to persist read permission for directory", null)
            return
        }

        val requestGeneration = lifecycleGeneration
        ioExecutor.execute {
            var displayName: String? = null
            try {
                val docId = DocumentsContract.getTreeDocumentId(treeUri)
                val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                contentResolver.query(
                    docUri,
                    arrayOf(OpenableColumns.DISPLAY_NAME, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                    null,
                    null,
                    null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        var idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (idx == -1) {
                            idx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                        }
                        if (idx != -1 && !cursor.isNull(idx)) {
                            val name = cursor.getString(idx)
                            if (!name.isNullOrBlank()) {
                                displayName = name
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to query document tree display name; fallback to last path segment")
            }

            if (displayName.isNullOrBlank()) {
                displayName = treeUri.lastPathSegment ?: "SAF 媒体源"
            }

            mainHandler.post {
                if (lifecycleGeneration != requestGeneration || isDestroyed || isFinishing) {
                    callback.error("ACTIVITY_DESTROYED", "Activity was destroyed before selection finished", null)
                    return@post
                }
                callback.success(
                    mapOf(
                        "rootLocator" to treeUri.toString(),
                        "name" to displayName
                    )
                )
            }
        }
    }

    private fun handleListChildren(call: MethodCall, result: MethodChannel.Result) {
        val treeUriString = call.argument<String>("treeUri")
        if (treeUriString.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "treeUri cannot be empty", null)
            return
        }

        val treeUri = try {
            Uri.parse(treeUriString)
        } catch (e: Exception) {
            result.error("INVALID_ARGUMENT", "Malformed treeUri", null)
            return
        }

        if (treeUri.scheme?.lowercase() != "content") {
            result.error("INVALID_SCHEME", "Only content URI is supported", null)
            return
        }

        val parentUriString = call.argument<String>("parentUri")
        val offset = call.argument<Number>("offset")?.toInt() ?: 0
        val limit = call.argument<Number>("limit")?.toInt() ?: 100

        val requestGeneration = lifecycleGeneration
        ioExecutor.execute {
            try {
                val parentDocId: String = if (parentUriString.isNullOrBlank() || parentUriString == treeUriString) {
                    DocumentsContract.getTreeDocumentId(treeUri)
                } else {
                    try {
                        val pUri = Uri.parse(parentUriString)
                        if (pUri.scheme?.lowercase() == "content") {
                            try {
                                DocumentsContract.getDocumentId(pUri)
                            } catch (e: Exception) {
                                parentUriString
                            }
                        } else {
                            parentUriString
                        }
                    } catch (e: Exception) {
                        parentUriString
                    }
                }

                val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
                val projection = arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED
                )

                val cursor = contentResolver.query(childrenUri, projection, null, null, null)
                if (cursor == null) {
                    mainHandler.post {
                        if (lifecycleGeneration == requestGeneration && !isDestroyed && !isFinishing) {
                            result.error("QUERY_FAILED", "Null cursor returned when querying directory children", null)
                        }
                    }
                    return@execute
                }

                cursor.use { c ->
                    val totalCount = c.count
                    val entries = ArrayList<Map<String, Any?>>()

                    if (offset in 0 until totalCount && c.moveToPosition(offset)) {
                        val docIdIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                        val nameIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                        val mimeIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                        val sizeIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                        val lastModIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)

                        var count = 0
                        do {
                            val childDocId = if (docIdIdx != -1 && !c.isNull(docIdIdx)) c.getString(docIdIdx) else null
                            if (!childDocId.isNullOrEmpty()) {
                                val name = if (nameIdx != -1 && !c.isNull(nameIdx)) c.getString(nameIdx) ?: "" else ""
                                val mimeType = if (mimeIdx != -1 && !c.isNull(mimeIdx)) c.getString(mimeIdx) ?: "" else ""
                                val isDirectory = mimeType == DocumentsContract.Document.MIME_TYPE_DIR
                                val size = if (sizeIdx != -1 && !c.isNull(sizeIdx)) c.getLong(sizeIdx) else null
                                val lastModified = if (lastModIdx != -1 && !c.isNull(lastModIdx)) c.getLong(lastModIdx) else null
                                val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childDocId).toString()

                                entries.add(
                                    mapOf(
                                        "externalId" to docUri,
                                        "locator" to docUri,
                                        "name" to name,
                                        "isDirectory" to isDirectory,
                                        "size" to size,
                                        "modifiedAt" to lastModified,
                                        "mimeType" to mimeType
                                    )
                                )
                            }
                            count++
                        } while (count < limit && c.moveToNext())
                    }

                    val hasMore = (offset + entries.size) < totalCount

                    mainHandler.post {
                        if (lifecycleGeneration != requestGeneration || isDestroyed || isFinishing) {
                            result.error("ACTIVITY_DESTROYED", "Activity was detached before query finished", null)
                            return@post
                        }
                        result.success(
                            mapOf(
                                "entries" to entries,
                                "hasMore" to hasMore,
                                "total" to totalCount
                            )
                        )
                    }
                }
            } catch (e: SecurityException) {
                Log.w(TAG, "SecurityException listing directory children")
                mainHandler.post {
                    if (lifecycleGeneration == requestGeneration && !isDestroyed && !isFinishing) {
                        result.error("SECURITY_ERROR", "Permission denied accessing directory children", null)
                    }
                }
            } catch (e: FileNotFoundException) {
                Log.w(TAG, "FileNotFoundException listing directory children")
                mainHandler.post {
                    if (lifecycleGeneration == requestGeneration && !isDestroyed && !isFinishing) {
                        result.error("FILE_NOT_FOUND", "Directory not found", null)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to list directory children")
                mainHandler.post {
                    if (lifecycleGeneration == requestGeneration && !isDestroyed && !isFinishing) {
                        result.error("IO_ERROR", "Failed to list directory children", null)
                    }
                }
            }
        }
    }

    private fun handleStatDocument(call: MethodCall, result: MethodChannel.Result) {
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

        if (uri.scheme?.lowercase() != "content") {
            result.error("INVALID_SCHEME", "Only content URI is supported", null)
            return
        }

        val requestGeneration = lifecycleGeneration
        ioExecutor.execute {
            try {
                val queryUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    if (DocumentsContract.isTreeUri(uri) && !DocumentsContract.isDocumentUri(this, uri)) {
                        try {
                            val treeDocId = DocumentsContract.getTreeDocumentId(uri)
                            DocumentsContract.buildDocumentUriUsingTree(uri, treeDocId)
                        } catch (e: Exception) {
                            uri
                        }
                    } else {
                        uri
                    }
                } else {
                    uri
                }

                val projection = arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED
                )

                val cursor = contentResolver.query(queryUri, projection, null, null, null)
                if (cursor == null) {
                    mainHandler.post {
                        if (lifecycleGeneration == requestGeneration && !isDestroyed && !isFinishing) {
                            result.error("FILE_NOT_FOUND", "Document not found or inaccessible", null)
                        }
                    }
                    return@execute
                }

                cursor.use { c ->
                    if (!c.moveToFirst()) {
                        mainHandler.post {
                            if (lifecycleGeneration == requestGeneration && !isDestroyed && !isFinishing) {
                                result.error("FILE_NOT_FOUND", "Document not found", null)
                            }
                        }
                        return@execute
                    }

                    val nameIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                    val mimeIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                    val sizeIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                    val lastModIdx = c.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)

                    val name = if (nameIdx != -1 && !c.isNull(nameIdx)) c.getString(nameIdx) else null
                    val mimeType = if (mimeIdx != -1 && !c.isNull(mimeIdx)) c.getString(mimeIdx) else null
                    val isDirectory = mimeType == DocumentsContract.Document.MIME_TYPE_DIR
                    val size = if (sizeIdx != -1 && !c.isNull(sizeIdx)) c.getLong(sizeIdx) else null
                    val lastModified = if (lastModIdx != -1 && !c.isNull(lastModIdx)) c.getLong(lastModIdx) else null

                    mainHandler.post {
                        if (lifecycleGeneration == requestGeneration && !isDestroyed && !isFinishing) {
                            result.success(
                                mapOf(
                                    "name" to name,
                                    "isDirectory" to isDirectory,
                                    "size" to size,
                                    "modifiedAt" to lastModified,
                                    "mimeType" to mimeType
                                )
                            )
                        }
                    }
                }
            } catch (e: SecurityException) {
                Log.w(TAG, "SecurityException querying document stat")
                mainHandler.post {
                    if (lifecycleGeneration == requestGeneration && !isDestroyed && !isFinishing) {
                        result.error("SECURITY_ERROR", "Permission denied accessing document", null)
                    }
                }
            } catch (e: FileNotFoundException) {
                Log.w(TAG, "FileNotFoundException querying document stat")
                mainHandler.post {
                    if (lifecycleGeneration == requestGeneration && !isDestroyed && !isFinishing) {
                        result.error("FILE_NOT_FOUND", "Document not found", null)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to query document stat")
                mainHandler.post {
                    if (lifecycleGeneration == requestGeneration && !isDestroyed && !isFinishing) {
                        result.error("IO_ERROR", "Failed to query document stat", null)
                    }
                }
            }
        }
    }

    private fun handleParentDocument(call: MethodCall, result: MethodChannel.Result) {
        val treeUriString = call.argument<String>("treeUri")
        val documentUriString = call.argument<String>("documentUri")
        if (treeUriString.isNullOrBlank() || documentUriString.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Tree and document URI are required", null)
            return
        }
        val requestGeneration = lifecycleGeneration
        ioExecutor.execute {
            try {
                val treeUri = Uri.parse(treeUriString)
                val documentUri = Uri.parse(documentUriString)
                require(treeUri.scheme == "content" && documentUri.authority == treeUri.authority)
                val scopedUri = DocumentsContract.buildDocumentUriUsingTree(
                    treeUri, DocumentsContract.getDocumentId(documentUri)
                )
                val path = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    try {
                        DocumentsContract.findDocumentPath(contentResolver, scopedUri)?.path
                    } catch (e: UnsupportedOperationException) {
                        null
                    }
                } else null
                val parent = if (path != null && path.size >= 2 &&
                    path.first() == DocumentsContract.getTreeDocumentId(treeUri)) {
                    DocumentsContract.buildDocumentUriUsingTree(treeUri, path[path.size - 2]).toString()
                } else null
                mainHandler.post {
                    if (lifecycleGeneration != requestGeneration || isDestroyed || isFinishing) {
                        result.error("ACTIVITY_DESTROYED", "Activity detached before query finished", null)
                    } else {
                        result.success(parent)
                    }
                }
            } catch (e: SecurityException) {
                mainHandler.post { result.error("SECURITY_ERROR", "Permission denied accessing document", null) }
            } catch (e: Exception) {
                mainHandler.post { result.error("IO_ERROR", "Unable to locate document directory", null) }
            }
        }
    }


    private fun readDocumentBytes(uri: Uri, limit: Int): ByteArray =
        contentResolver.openInputStream(uri).use { input ->
            checkNotNull(input)
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                require(output.size() + count <= limit) { "File too large" }
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        }

    private fun handleReadDocument(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Document URI is required", null)
            return
        }
        val uri = Uri.parse(uriString)
        if (uri.scheme != "content") {
            result.error("INVALID_SCHEME", "Only content URI is supported", null)
            return
        }
        val generation = lifecycleGeneration
        val limit = (call.argument<Number>("maxBytes")?.toInt() ?: 2097152).coerceIn(1, 16777216)
        ioExecutor.execute {
            try {
                val bytes = readDocumentBytes(uri, limit)
                mainHandler.post {
                    if (lifecycleGeneration == generation && !isDestroyed && !isFinishing) result.success(bytes)
                    else result.error("ACTIVITY_DESTROYED", "Activity detached", null)
                }
            } catch (e: SecurityException) {
                mainHandler.post { result.error("SECURITY_ERROR", "Document read permission is required", null) }
            } catch (e: IllegalArgumentException) {
                mainHandler.post { result.error("FILE_TOO_LARGE", "Document exceeds size limit", null) }
            } catch (e: Exception) {
                mainHandler.post { result.error("IO_ERROR", "Unable to read document", null) }
            }
        }
    }

    private fun handleSidecar(call: MethodCall, result: MethodChannel.Result, write: Boolean) {
        val treeString = call.argument<String>("treeUri")
        val targetString = call.argument<String>(if (write) "directoryUri" else "uri")
        if (treeString.isNullOrBlank() || targetString.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "Directory and document are required", null)
            return
        }
        val generation = lifecycleGeneration
        ioExecutor.execute {
            try {
                val tree = Uri.parse(treeString)
                val target = Uri.parse(targetString)
                require(tree.scheme == "content" && target.authority == tree.authority)
                val treeId = DocumentsContract.getTreeDocumentId(tree)
                val documentId = if (target == tree) treeId else DocumentsContract.getDocumentId(target)
                val scoped = DocumentsContract.buildDocumentUriUsingTree(tree, documentId)
                val value: Any? = if (!write) {
                    val limit = (call.argument<Number>("maxBytes")?.toInt() ?: 2097152).coerceIn(1, 16777216)
                    readDocumentBytes(scoped, limit)
                } else {
                    if (!contentResolver.persistedUriPermissions.any {
                        it.uri == tree && it.isWritePermission
                    }) throw SecurityException("Write permission is required")
                    val name = call.argument<String>("name") ?: ""
                    require(name.isNotEmpty() && name != "." && name != ".." &&
                        !name.contains('/') && !name.contains('\\') && !name.contains('\u0000'))
                    val bytes = requireNotNull(call.argument<ByteArray>("bytes"))
                    require(bytes.size <= 16777216)
                    val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, documentId)
                    var existing: Uri? = null
                    contentResolver.query(children, arrayOf(
                        DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME
                    ), null, null, null).use { cursor ->
                        requireNotNull(cursor)
                        while (cursor.moveToNext()) {
                            if (cursor.getString(1) == name) {
                                existing = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0))
                                break
                            }
                        }
                    }
                    if (existing == null || call.argument<Boolean>("createOnly") != true) {
                        val mime = if (name.endsWith(".jpg", true)) "image/jpeg" else "application/octet-stream"
                        val outputUri = existing ?: requireNotNull(DocumentsContract.createDocument(contentResolver, scoped, mime, name))
                        val previous = existing?.let { uri ->
                            contentResolver.openInputStream(uri).use { input ->
                                requireNotNull(input)
                                val old = ByteArrayOutputStream()
                                val buffer = ByteArray(65536)
                                while (true) {
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    require(old.size() + count <= 16777216)
                                    old.write(buffer, 0, count)
                                }
                                old.toByteArray()
                            }
                        }
                        try {
                            contentResolver.openOutputStream(outputUri, "wt").use { output ->
                                requireNotNull(output)
                                output.write(bytes)
                                output.flush()
                            }
                        } catch (e: Exception) {
                            try {
                                if (previous == null) DocumentsContract.deleteDocument(contentResolver, outputUri)
                                else contentResolver.openOutputStream(outputUri, "wt").use { it?.write(previous) }
                            } catch (_: Exception) { }
                            throw e
                        }
                    }
                    null
                }
                mainHandler.post {
                    if (lifecycleGeneration == generation && !isDestroyed && !isFinishing) result.success(value)
                    else result.error("ACTIVITY_DESTROYED", "Activity detached", null)
                }
            } catch (e: SecurityException) {
                mainHandler.post { result.error("SECURITY_ERROR", "Directory write permission is required", null) }
            } catch (e: Exception) {
                mainHandler.post { result.error("IO_ERROR", "Unable to access metadata file", null) }
            }
        }
    }

    private fun handleCheckPermission(call: MethodCall, result: MethodChannel.Result) {
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

        val granted = try {
            contentResolver.persistedUriPermissions.any {
                it.uri == uri && it.isReadPermission
            }
        } catch (e: Exception) {
            false
        }
        result.success(granted)
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
        pendingDirectoryPickerResult?.let { pending ->
            pendingDirectoryPickerResult = null
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
