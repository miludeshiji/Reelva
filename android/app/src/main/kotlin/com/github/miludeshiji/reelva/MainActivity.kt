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
        private const val REQUEST_CODE_PICK_DIRECTORY = 1002
    }

    private var channel: MethodChannel? = null
    private var pendingPickerResult: MethodChannel.Result? = null
    private var pendingDirectoryPickerResult: MethodChannel.Result? = null
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
            "pickDirectory" -> handlePickDirectory(call, result)
            "listChildren" -> handleListChildren(call, result)
            "statDocument" -> handleStatDocument(call, result)
            "checkPermission" -> handleCheckPermission(call, result)
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

    private fun handlePickDirectory(call: MethodCall, result: MethodChannel.Result) {
        if (pendingPickerResult != null || pendingDirectoryPickerResult != null) {
            result.error("ALREADY_ACTIVE", "A media picker is already active", null)
            return
        }

        val initialLocator = call.argument<String>("initialLocator")
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
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

        val takeFlags = data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION
        if (takeFlags == 0) {
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
