package com.splitup.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.splitup.app/installer"
    private val TAG = "SplitUpInstaller"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestPackageInstalls" -> {
                    try {
                        val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                        Log.i(TAG, "canRequestPackageInstalls check: $canInstall")
                        result.success(canInstall)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error checking install permission", e)
                        result.error("PERMISSION_CHECK_ERROR", e.message, null)
                    }
                }
                "openInstallPermissionSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            Log.i(TAG, "Launching ACTION_MANAGE_UNKNOWN_APP_SOURCES for $packageName")
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error opening install settings", e)
                        result.error("SETTINGS_OPEN_ERROR", e.message, null)
                    }
                }
                "getDownloadPath" -> {
                    try {
                        val updateDir = File(filesDir, "ota_update")
                        if (!updateDir.exists()) {
                            updateDir.mkdirs()
                        }
                        val apkFile = File(updateDir, "splitup-update.apk")
                        Log.i(TAG, "Resolved download path: ${apkFile.absolutePath}")
                        result.success(apkFile.absolutePath)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting download path", e)
                        result.error("PATH_ERROR", e.message, null)
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrEmpty()) {
                        Log.e(TAG, "installApk called with empty filePath")
                        result.error("INVALID_PATH", "APK file path cannot be null or empty", null)
                        return@setMethodCallHandler
                    }

                    val apkFile = File(filePath)
                    if (!apkFile.exists()) {
                        Log.e(TAG, "installApk failed: file does not exist at $filePath")
                        result.error("FILE_NOT_FOUND", "APK file does not exist at: $filePath", null)
                        return@setMethodCallHandler
                    }

                    val fileSize = apkFile.length()
                    Log.i(TAG, "Starting install intent for APK: ${apkFile.absolutePath} ($fileSize bytes)")
                    if (fileSize <= 0) {
                        Log.e(TAG, "installApk failed: file size is 0 bytes")
                        result.error("EMPTY_FILE", "APK file is empty (0 bytes)", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val authority = "$packageName.ota_update_provider"
                        val contentUri = FileProvider.getUriForFile(this, authority, apkFile)
                        Log.i(TAG, "Created content URI for install: $contentUri")

                        val installIntent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(contentUri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }

                        startActivity(installIntent)
                        Log.i(TAG, "startActivity(installIntent) completed successfully")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error starting installer activity", e)
                        result.error("INSTALL_LAUNCH_ERROR", e.message, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
