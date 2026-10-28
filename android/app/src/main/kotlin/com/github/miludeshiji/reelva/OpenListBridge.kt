package com.github.miludeshiji.reelva

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import openlistcore.Openlistcore

/** Runs the synchronous embedded core RPC off the Android UI thread. */
class OpenListBridge(messenger: BinaryMessenger) : AutoCloseable {
    private val channel = MethodChannel(messenger, "reelva/openlist")
    private val mainHandler = Handler(Looper.getMainLooper())
    // Cancellation RPCs must remain able to run while a file operation is waiting.
    private val executor = Executors.newCachedThreadPool()

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "invoke") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val request = call.arguments as? String
            if (request == null) {
                result.error("invalid_request", "OpenList requires a JSON string", null)
                return@setMethodCallHandler
            }
            executor.execute {
                try {
                    val response = Openlistcore.invoke(request)
                    mainHandler.post { result.success(response) }
                } catch (error: Throwable) {
                    // Provider exceptions may contain signed URLs or credentials.
                    mainHandler.post {
                        result.error("openlist", "OpenList core operation failed", null)
                    }
                }
            }
        }
    }

    override fun close() {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }
}
