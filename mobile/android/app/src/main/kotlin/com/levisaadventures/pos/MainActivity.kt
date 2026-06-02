package com.levisaadventures.pos

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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

					else -> result.notImplemented()
				}
			}
	}
}
