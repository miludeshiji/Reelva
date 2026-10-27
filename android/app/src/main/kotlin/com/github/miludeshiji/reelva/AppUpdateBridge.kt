package com.github.miludeshiji.reelva

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class AppUpdateFileProvider : FileProvider()

class AppUpdateBridge(private val activity: Activity, messenger: BinaryMessenger) {
    companion object {
        private const val REQUEST_INSTALL_PERMISSION = 1003
        private const val PENDING_APK = "pending_apk"
    }

    private val preferences = activity.getSharedPreferences("reelva_app_update", Activity.MODE_PRIVATE)
    private val channel = MethodChannel(messenger, "reelva/app_update")
    private var pendingResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
            "installApk" -> {
                if (pendingResult != null) {
                    result.error("ALREADY_ACTIVE", "An install request is already active", null)
                    return
                }
                try {
                    val file = apkFile(call.argument<String>("path"))
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !activity.packageManager.canRequestPackageInstalls()) {
                        preferences.edit().putString(PENDING_APK, file.path).apply()
                        pendingResult = result
                        activity.startActivityForResult(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${activity.packageName}")),
                            REQUEST_INSTALL_PERMISSION
                        )
                    } else {
                        openInstaller(file)
                        result.success(true)
                    }
                } catch (_: Exception) {
                    preferences.edit().remove(PENDING_APK).apply()
                    pendingResult = null
                    result.error("INSTALL_FAILED", "Unable to open package installer", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun apkFile(path: String?): File {
        require(!path.isNullOrBlank())
        val directory = File(activity.cacheDir, "updates").canonicalFile
        val file = File(path).canonicalFile
        require(file.parentFile == directory && file.isFile && file.extension == "apk")
        return file
    }

    private fun openInstaller(file: File) {
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.app_update", file)
        activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
    }

    fun onActivityResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_INSTALL_PERMISSION) return false
        val result = pendingResult
        pendingResult = null
        val path = preferences.getString(PENDING_APK, null)
        preferences.edit().remove(PENDING_APK).apply()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !activity.packageManager.canRequestPackageInstalls()) {
                result?.success(false)
            } else if (path != null) {
                openInstaller(apkFile(path))
                result?.success(true)
            } else {
                result?.success(false)
            }
        } catch (_: Exception) {
            result?.error("INSTALL_FAILED", "Unable to open package installer", null)
        }
        return true
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pendingResult?.success(false)
        pendingResult = null
    }
}
