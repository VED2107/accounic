package com.accounic.app

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Saves exports into the phone's public Downloads folder, under Download/Accounic.
 *
 * The app used to write to getExternalStorageDirectory(), which is
 * Android/data/com.accounic.app/files. Since Android 11 that folder is hidden
 * from the Files app and most file managers, so a saved statement was
 * effectively lost. MediaStore.Downloads is the public Downloads collection:
 * the file shows up in Files, in Downloads, and in any PDF reader's picker,
 * and on Android 10+ writing there needs no permission at all.
 *
 * Android 9 and older have no MediaStore.Downloads, so there the file goes to
 * the public Download directory directly, which needs WRITE_EXTERNAL_STORAGE
 * (declared with maxSdkVersion=28 in the manifest, so newer phones never ask).
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.accounic.app/downloads"
    private val subfolder = "Accounic"
    private val storagePermissionRequest = 4107

    /** A save waiting on the legacy storage permission prompt. */
    private var pendingSave: Pair<MethodCall, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "save" -> save(call, result)
                    "open" -> open(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun save(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("name")
        val mime = call.argument<String>("mime") ?: "application/octet-stream"
        val bytes = call.argument<ByteArray>("bytes")
        if (name.isNullOrBlank() || bytes == null) {
            result.error("bad_args", "A file name and its contents are required.", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveWithMediaStore(name, mime, bytes, result)
            return
        }

        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingSave != null) {
                result.error("busy", "Another save is already waiting for permission.", null)
                return
            }
            pendingSave = call to result
            requestPermissions(
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                storagePermissionRequest,
            )
            return
        }
        saveLegacy(name, mime, bytes, result)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != storagePermissionRequest) return
        val (call, result) = pendingSave ?: return
        pendingSave = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            saveLegacy(
                call.argument<String>("name")!!,
                call.argument<String>("mime") ?: "application/octet-stream",
                call.argument<ByteArray>("bytes")!!,
                result,
            )
        } else {
            result.error(
                "permission",
                "Accounic needs storage access to save into Downloads.",
                null,
            )
        }
    }

    private fun saveWithMediaStore(
        name: String,
        mime: String,
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        val resolver = contentResolver
        val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/$subfolder"
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, mime)
            put(MediaStore.Downloads.RELATIVE_PATH, relativePath)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }

        var uri: Uri? = null
        try {
            uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Downloads refused the file.")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Downloads could not be opened for writing.")
            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) },
                null,
                null,
            )

            // MediaStore renames on a clash ("x-statement (1).pdf"), so read
            // back the name it actually used rather than reporting ours.
            var savedName = name
            resolver.query(uri, arrayOf(MediaStore.Downloads.DISPLAY_NAME), null, null, null)
                ?.use { cursor -> if (cursor.moveToFirst()) savedName = cursor.getString(0) }

            result.success(
                mapOf(
                    "path" to "Download/$subfolder/$savedName",
                    "uri" to uri.toString(),
                ),
            )
        } catch (error: Exception) {
            // Never leave a pending, half-written entry in Downloads.
            uri?.let { runCatching { resolver.delete(it, null, null) } }
            result.error("write_failed", error.message ?: "The file could not be saved.", null)
        }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(
        name: String,
        mime: String,
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        try {
            val directory = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                subfolder,
            )
            if (!directory.exists() && !directory.mkdirs()) {
                throw IllegalStateException("The Downloads folder could not be created.")
            }
            val file = uniqueFile(directory, name)
            file.writeBytes(bytes)
            // Without a scan, the file exists but Files and the Downloads app
            // will not list it until the next reboot.
            MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf(mime), null)
            result.success(
                mapOf(
                    "path" to file.absolutePath,
                    "uri" to Uri.fromFile(file).toString(),
                ),
            )
        } catch (error: Exception) {
            result.error("write_failed", error.message ?: "The file could not be saved.", null)
        }
    }

    private fun uniqueFile(directory: File, name: String): File {
        var file = File(directory, name)
        if (!file.exists()) return file
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val extension = if (dot > 0) name.substring(dot) else ""
        var n = 1
        while (file.exists()) {
            file = File(directory, "$base ($n)$extension")
            n++
        }
        return file
    }

    private fun open(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        val mime = call.argument<String>("mime") ?: "*/*"
        if (uriString.isNullOrBlank()) {
            result.success(false)
            return
        }
        val uri = Uri.parse(uriString)
        // file:// URIs cannot be handed to other apps on Android 7+; only the
        // MediaStore content:// URIs from Android 10+ can be opened from here.
        if (uri.scheme != "content") {
            result.success(false)
            return
        }
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(Intent.createChooser(intent, null).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.success(false)
        }
    }
}
