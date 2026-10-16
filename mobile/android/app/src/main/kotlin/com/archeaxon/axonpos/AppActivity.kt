package com.archeaxon.axonpos

import android.content.Intent
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
class MainActivity : FlutterFragmentActivity() {
	private val installerChannel = "pos_mobile/installer"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

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
									this@MainActivity,
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

