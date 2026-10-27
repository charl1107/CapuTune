package com.example.caputune

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : AudioServiceActivity() {
    private companion object {
        const val CHANNEL = "com.example.caputune/installer"
        const val APK_MIME = "application/vnd.android.package-archive"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Device ABIs, used to pick the right release APK variant.
                    "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                    // Only checked at the moment of installing, never at startup.
                    "canInstallPackages" -> result.success(canInstallPackages())
                    "openInstallSettings" -> result.success(openInstallSettings())
                    "installApk" -> installApk(call.argument<String>("path"), result)
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * The per-app "install unknown apps" grant. Android 8.0+ exposes it per app;
     * below that there is no per-app toggle, so installing is always allowed.
     */
    private fun canInstallPackages(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    /** Opens the system screen where the user grants that per-app grant. */
    private fun openInstallSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("invalid_path", "No APK path was provided", null)
            return
        }
        val apk = File(path)
        if (!apk.exists()) {
            result.error("missing_file", "The downloaded update file is missing", null)
            return
        }
        try {
            val problem = validateUpdate(apk)
            if (problem != null) {
                result.error("incompatible_apk", problem, null)
                return
            }
            startInstaller(apk)
            result.success(null)
        } catch (e: Exception) {
            result.error(
                "install_failed",
                e.message ?: "The installer could not be opened",
                null,
            )
        }
    }

    /**
     * Rejects, before launching anything, an APK that could not upgrade this
     * app: a different package, a version that is not newer (a downgrade), or a
     * different signing key. Android would refuse these itself; checking first
     * lets the app explain why instead of showing a generic installer failure.
     * Returns null when the update is a valid upgrade.
     */
    private fun validateUpdate(apk: File): String? {
        val flags = signingFlags()
        val archive = packageManager.getPackageArchiveInfo(apk.absolutePath, flags)
            ?: return "The update file could not be read"
        val archiveApp = archive.applicationInfo
            ?: return "The update file is not a valid app"

        if (archiveApp.packageName != packageName) {
            return "This update is for a different app (${archiveApp.packageName})"
        }

        val installed = try {
            packageManager.getPackageInfo(packageName, flags)
        } catch (_: PackageManager.NameNotFoundException) {
            return null
        }

        val newCode = archive.versionCodeCompat()
        val installedCode = installed.versionCodeCompat()
        if (newCode <= installedCode) {
            return "This update (version code $newCode) is not newer than the " +
                "installed version ($installedCode)"
        }

        val archiveSigners = signerDigests(archive)
        if (archiveSigners.isEmpty()) {
            return "The update file is not signed"
        }
        val installedSigners = signerDigests(installed)
        if (installedSigners.isNotEmpty() &&
            !archiveSigners.containsAll(installedSigners)
        ) {
            return "The update is signed with a different key than the installed app"
        }
        return null
    }

    private fun signingFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }

    /** SHA-256 digests of the signing certificates, as lowercase hex. */
    @Suppress("DEPRECATION")
    private fun signerDigests(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = info.signingInfo ?: return emptySet()
            if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners
            } else {
                signingInfo.signingCertificateHistory
            }
        } else {
            info.signatures
        } ?: return emptySet()
        return signatures.mapTo(mutableSetOf()) { sha256(it.toByteArray()) }
    }

    private fun sha256(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString(separator = "") { "%02x".format(it.toInt() and 0xff) }
    }

    @Suppress("DEPRECATION")
    private fun PackageInfo.versionCodeCompat(): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) longVersionCode
        else versionCode.toLong()

    /**
     * Opens Android's package installer for [apk]. The system shows its own
     * confirmation dialog and verifies the APK signature against the installed
     * app, so an update can never be applied silently.
     */
    private fun startInstaller(apk: File) {
        val uri: Uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, APK_MIME)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
