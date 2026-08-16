package com.conquerclub.app

import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.conquerclub.app/social_share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareToInstagramStory" -> {
                    val imagePath = call.argument<String>("imagePath")
                    if (imagePath == null) {
                        result.error("BAD_ARGS", "imagePath is required", null)
                        return@setMethodCallHandler
                    }
                    result.success(shareToInstagramStory(imagePath))
                }
                "shareToSnapchat" -> {
                    val imagePath = call.argument<String>("imagePath")
                    if (imagePath == null) {
                        result.error("BAD_ARGS", "imagePath is required", null)
                        return@setMethodCallHandler
                    }
                    result.success(shareToSnapchat(imagePath))
                }
                "isAppInstalled" -> {
                    val packageName = call.argument<String>("packageName")
                    result.success(isPackageInstalled(packageName))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isPackageInstalled(packageName: String?): Boolean {
        if (packageName == null) return false
        return try {
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun contentUriFor(imagePath: String) = FileProvider.getUriForFile(
        this,
        "$packageName.socialshare.fileprovider",
        File(imagePath)
    )

    // Opens straight into Instagram's Story editor with the image already
    // placed as the background. No Facebook App ID needed for this basic
    // form (attribution requires one, but the share itself does not).
    private fun shareToInstagramStory(imagePath: String): Boolean {
        if (!isPackageInstalled("com.instagram.android")) return false

        val uri = contentUriFor(imagePath)
        val intent = Intent("com.instagram.share.ADD_TO_STORY").apply {
            setDataAndType(uri, "image/jpeg")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            setPackage("com.instagram.android")
        }
        grantUriPermission("com.instagram.android", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)

        return if (intent.resolveActivity(packageManager) != null) {
            startActivity(intent)
            true
        } else {
            false
        }
    }

    // Opens directly into Snapchat with the image loaded, ready to post
    // as a Snap/Story. This uses a direct-package ACTION_SEND intent
    // (works without the Snap Creative Kit SDK). For the fully-featured
    // Creative Kit flow (custom stickers, attribution), Snap Kit
    // credentials would be needed instead.
    private fun shareToSnapchat(imagePath: String): Boolean {
        if (!isPackageInstalled("com.snapchat.android")) return false

        val uri = contentUriFor(imagePath)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "image/*"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            setPackage("com.snapchat.android")
        }
        grantUriPermission("com.snapchat.android", uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)

        return if (intent.resolveActivity(packageManager) != null) {
            startActivity(intent)
            true
        } else {
            false
        }
    }
}
