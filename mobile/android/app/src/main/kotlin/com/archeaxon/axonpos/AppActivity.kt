package com.archeaxon.axonpos

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// local_auth needs the host Activity to be a FragmentActivity to show the
// BiometricPrompt — plain FlutterActivity makes canCheckBiometrics/authenticate
// silently report "unavailable" instead of throwing, so the biometric unlock
// button on the PIN screen just never appears.
class AppActivity : FlutterFragmentActivity() {
	private val installerChannel = "pos_mobile/installer"
	private val appIconChannel = "axon_pos/app_icon"

	// Launcher entries declared as <activity-alias> in AndroidManifest.xml. The
	// standard one keeps the original ".MainActivity" component name so home-screen
	// shortcuts made before aliases existed keep working.
	private val iconAliases = linkedMapOf(
		"standard" to "MainActivity",
		"streak" to "IconStreak",
		"alert" to "IconAlert",
		"gold" to "IconGold",
	)

	private fun aliasComponent(simpleName: String) =
		ComponentName(packageName, "com.archeaxon.axonpos.$simpleName")

	private fun isAliasEnabled(key: String): Boolean {
		val state = packageManager.getComponentEnabledSetting(aliasComponent(iconAliases.getValue(key)))
		return when (state) {
			PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
			PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
			// DEFAULT = whatever the manifest says: only the standard alias is on.
			else -> key == "standard"
		}
	}

	private fun currentIcon(): String =
		iconAliases.keys.firstOrNull { isAliasEnabled(it) } ?: "standard"

	/** Enables [key]'s launcher entry first, then disables the rest, so there is
	 *  never a moment with no launcher icon. DONT_KILL_APP keeps the app running. */
	private fun switchIcon(key: String) {
		packageManager.setComponentEnabledSetting(
			aliasComponent(iconAliases.getValue(key)),
			PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
			PackageManager.DONT_KILL_APP,
		)
		for ((other, name) in iconAliases) {
			if (other == key) continue
			packageManager.setComponentEnabledSetting(
				aliasComponent(name),
				PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
				PackageManager.DONT_KILL_APP,
			)
		}
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appIconChannel)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"getIcon" -> result.success(currentIcon())

					"pinCurrentIcon" -> {
						// Asks the launcher to put the CURRENT icon on the home screen
						// (the user confirms in a system dialog). Used to restore the
						// shortcut a launcher may drop when the icon is switched.
						if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
							result.success(false)
							return@setMethodCallHandler
						}
						try {
							val shortcuts = getSystemService(ShortcutManager::class.java)
							if (shortcuts == null || !shortcuts.isRequestPinShortcutSupported) {
								result.success(false)
								return@setMethodCallHandler
							}
							val key = currentIcon()
							val launch = Intent(Intent.ACTION_MAIN).apply {
								addCategory(Intent.CATEGORY_LAUNCHER)
								component = aliasComponent(iconAliases.getValue(key))
							}
							val mipmap = if (key == "standard") "ic_launcher" else "ic_launcher_$key"
							val iconRes = resources.getIdentifier(mipmap, "mipmap", packageName)
							val info = ShortcutInfo.Builder(this@AppActivity, "axon_pos_home_$key")
								.setShortLabel("Axon POS")
								.setIcon(Icon.createWithResource(this@AppActivity, iconRes))
								.setIntent(launch)
								.build()
							result.success(shortcuts.requestPinShortcut(info, null))
						} catch (error: Exception) {
							result.error("PIN_ERROR", error.message, null)
						}
					}

					"setIcon" -> {
						val key = call.argument<String>("key")
						if (key == null || !iconAliases.containsKey(key)) {
							result.error("UNKNOWN_ICON", "No launcher icon named $key", null)
							return@setMethodCallHandler
						}
						try {
							if (currentIcon() != key) switchIcon(key)
							result.success(true)
						} catch (error: Exception) {
							result.error("ICON_ERROR", error.message, null)
						}
					}

					else -> result.notImplemented()
				}
			}

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installerChannel)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"canRequestPackageInstalls" -> {
						val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
							packageManager.canRequestPackageInstalls()
						} else {
							true
						}
						result.success(canInstall)
					}

					"openUnknownSourcesSettings" -> {
						try {
							val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
								Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
									data = Uri.parse("package:$packageName")
								}
							} else {
								Intent(Settings.ACTION_SECURITY_SETTINGS)
							}

							intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
							startActivity(intent)
							result.success(true)
						} catch (error: Exception) {
							result.error(
								"INSTALL_SETTINGS_ERROR",
								error.message,
								null,
							)
						}
					}

					"installApk" -> {
						val path = call.argument<String>("apkPath")
						if (path.isNullOrBlank()) {
							result.error("INVALID_PATH", "APK path is required", null)
							return@setMethodCallHandler
						}

						try {
							val file = File(path)
							if (!file.exists()) {
								result.error("FILE_NOT_FOUND", "APK not found at $path", null)
								return@setMethodCallHandler
							}

							val apkUri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
								FileProvider.getUriForFile(
									this@AppActivity,
									"$packageName.fileprovider",
									file,
								)
							} else {
								Uri.fromFile(file)
							}

							val intent = Intent(Intent.ACTION_VIEW).apply {
								setDataAndType(
									apkUri,
									"application/vnd.android.package-archive",
								)
								addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
								addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
							}

							startActivity(intent)
							result.success(true)
						} catch (error: Exception) {
							result.error(
								"INSTALL_ERROR",
								error.message,
								null,
							)
						}
					}

					else -> result.notImplemented()
				}
			}
	}
}

