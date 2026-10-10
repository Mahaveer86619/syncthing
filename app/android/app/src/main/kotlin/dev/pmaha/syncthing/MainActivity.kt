package dev.pmaha.syncthing

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        LauncherIcon.schedule(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "syncthing/launcher_icon")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "festival" -> result.success(
                        Festivals.on(LocalDate.now())?.let {
                            mapOf("id" to it.id, "greeting" to it.greeting, "emoji" to it.emoji)
                        },
                    )
                    "getMode" -> result.success(LauncherIcon.mode(this))
                    "setMode" -> {
                        LauncherIcon.setMode(this, call.arguments as String)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Swapping the alias while the app is on screen can make some launchers close it,
    // so changes are applied once the user leaves.
    override fun onStop() {
        super.onStop()
        LauncherIcon.apply(this)
    }
}
