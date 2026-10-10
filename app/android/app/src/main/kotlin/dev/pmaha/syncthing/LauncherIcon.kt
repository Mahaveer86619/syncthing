package dev.pmaha.syncthing

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.time.LocalDate
import java.util.concurrent.TimeUnit

data class Festival(val id: String, val icon: String, val greeting: String, val emoji: String)

object Festivals {
    private val newYear = Festival("newyear", "newyear", "Happy New Year", "🎆")
    private val republicDay = Festival("republic", "tricolor", "Happy Republic Day", "🇮🇳")
    private val holi = Festival("holi", "holi", "Happy Holi", "🎨")
    private val independenceDay = Festival("independence", "tricolor", "Happy Independence Day", "🇮🇳")
    private val diwali = Festival("diwali", "diwali", "Happy Diwali", "🪔")
    private val christmas = Festival("christmas", "christmas", "Merry Christmas", "🎄")

    // Lunar-calendar festivals move every year, so they are listed per year; extend this table yearly.
    private val lunar = listOf(
        LocalDate.of(2026, 11, 5)..LocalDate.of(2026, 11, 10) to diwali,
        LocalDate.of(2027, 3, 20)..LocalDate.of(2027, 3, 23) to holi,
        LocalDate.of(2027, 10, 26)..LocalDate.of(2027, 10, 31) to diwali,
        LocalDate.of(2028, 3, 9)..LocalDate.of(2028, 3, 12) to holi,
        LocalDate.of(2028, 10, 14)..LocalDate.of(2028, 10, 19) to diwali,
    )

    fun on(date: LocalDate): Festival? {
        val md = date.monthValue * 100 + date.dayOfMonth
        return when {
            md >= 1231 || md <= 102 -> newYear
            md in 124..127 -> republicDay
            md in 813..816 -> independenceDay
            md in 1220..1226 -> christmas
            else -> lunar.firstOrNull { date in it.first }?.second
        }
    }
}

/** Swaps the launcher icon by enabling one `Icon_<name>` activity-alias and disabling the rest. */
object LauncherIcon {
    val icons = listOf("default", "mono", "diwali", "holi", "christmas", "newyear", "tricolor")

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("launcher_icon", Context.MODE_PRIVATE)

    /** "auto" (Dynamic) follows the festival calendar; "mono" pins the grey icon. */
    fun mode(ctx: Context): String = prefs(ctx).getString("mode", "auto") ?: "auto"

    fun setMode(ctx: Context, mode: String) = prefs(ctx).edit().putString("mode", mode).apply()

    private fun wanted(ctx: Context): String {
        val mode = mode(ctx)
        return if (mode == "auto") Festivals.on(LocalDate.now())?.icon ?: "default" else mode
    }

    fun apply(ctx: Context) {
        val pm = ctx.packageManager
        val want = wanted(ctx)
        // Enable the new alias before disabling the old one so the app never vanishes from the launcher.
        for (icon in listOf(want) + icons.filter { it != want }) {
            val alias = ComponentName(ctx, "${ctx.packageName}.Icon_$icon")
            val enabled = icon == want
            val current = pm.getComponentEnabledSetting(alias)
            val isEnabled = current == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (current == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && icon == "default")
            if (isEnabled == enabled) continue
            pm.setComponentEnabledSetting(
                alias,
                if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }

    fun schedule(ctx: Context) {
        val request = PeriodicWorkRequest.Builder(IconWorker::class.java, 12, TimeUnit.HOURS).build()
        WorkManager.getInstance(ctx)
            .enqueueUniquePeriodicWork("launcher-icon", ExistingPeriodicWorkPolicy.KEEP, request)
    }
}

class IconWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    override fun doWork(): Result {
        LauncherIcon.apply(applicationContext)
        return Result.success()
    }
}
