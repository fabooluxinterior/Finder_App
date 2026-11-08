package com.finderapp.finder

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // FLAG_SECURE before the Flutter surface attaches: blocks screenshots,
        // screen recording, casting to insecure displays and Recents thumbnails
        // on every screen (deck, profiles, requests, chat).
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Back on the home screen sends the app to the background (like the
        // Home button) instead of closing it, so nothing restarts.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vouby/app").setMethodCallHandler { call, result ->
            if (call.method == "moveToBackground") {
                result.success(moveTaskToBack(true))
            } else {
                result.notImplemented()
            }
        }
    }
}
