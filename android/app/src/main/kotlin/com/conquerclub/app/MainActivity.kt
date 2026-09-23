package com.conquerclub.app

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.conquerclub.app/instagram_share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "shareToInstagramFeed") {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                try {
                    val file = File(path)
                    val uri = FileProvider.getUriForFile(
                        this,
                        "$packageName.shareprovider",
                        file
                    )
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "image/png"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        setPackage("com.instagram.android")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    // Instagram not installed, or anything else went wrong —
                    // Dart side falls back to the normal share sheet.
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
