package dev.pmaha.syncthing

import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate

class MainActivity : FlutterActivity() {
    override fun onResume() {
        super.onResume()
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
                    "scanQr" -> scanQr(result)
                    "openAutoStart" -> result.success(openAutoStart())
                    // WorkManager's own database still lists work an OEM battery manager deleted,
                    // so ask the system scheduler what is really pending.
                    "pendingJobs" -> result.success(getSystemService(JobScheduler::class.java).allPendingJobs.size)
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Play Services' scanner brings its own camera UI, so the app needs no camera permission.
     * It is an optional module fetched on demand; scanning before it is on the phone fails
     * straight away, so make sure it is installed first.
     */
    private fun scanQr(result: MethodChannel.Result) {
        val scanner = GmsBarcodeScanning.getClient(
            this,
            GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build(),
        )
        val fail = { e: Exception ->
            Log.w("syncthing", "QR scan failed", e)
            result.error("scan", e.message ?: e.javaClass.simpleName, null)
        }
        val start = {
            scanner.startScan()
                .addOnSuccessListener { result.success(it.rawValue) }
                .addOnCanceledListener { result.success(null) }
                .addOnFailureListener(fail)
        }
        val modules = ModuleInstall.getClient(this)
        modules.areModulesAvailable(scanner)
            .addOnSuccessListener { available ->
                if (available.areModulesAvailable()) {
                    start()
                } else {
                    modules.installModules(ModuleInstallRequest.newBuilder().addApi(scanner).build())
                        .addOnSuccessListener { start() }
                        .addOnFailureListener(fail)
                }
            }
            .addOnFailureListener(fail)
    }

    /**
     * Phone makers' battery managers (Infinix XOS "Hiber", MIUI, ColorOS...) delete an app's
     * scheduled jobs when it is swiped from Recents unless it is allowed to auto-start.
     * Opens that screen if this phone has one, else the app's info page. Returns true for the former.
     */
    private fun openAutoStart(): Boolean {
        val candidates = listOf(
            ComponentName("com.transsion.phonemaster", "com.cyin.himgr.autostart.AutoStartActivity"),
            ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
            ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
            ComponentName("com.oplus.safecenter", "com.oplus.safecenter.permission.startup.StartupAppListActivity"),
            ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
            ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
        )
        for (c in candidates) {
            val intent = Intent().setComponent(c).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (intent.resolveActivity(packageManager) != null) {
                try {
                    startActivity(intent)
                    return true
                } catch (e: Exception) {
                    continue
                }
            }
        }
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        return false
    }

    // Swapping the alias while the app is on screen can make some launchers close it,
    // so changes are applied once the user leaves.
    override fun onStop() {
        super.onStop()
        LauncherIcon.apply(this)
    }
}
