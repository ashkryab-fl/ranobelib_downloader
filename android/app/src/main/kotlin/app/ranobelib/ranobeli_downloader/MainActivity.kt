package app.ranobelib.ranobeli_downloader

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val fileExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.ranobelib/downloads")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "save" -> {
                        val path = call.argument<String>("path")
                        val name = call.argument<String>("name")
                        if (path == null || name == null) {
                            result.error("INVALID_ARGUMENT", "Немає файлу або назви EPUB.", null)
                        } else {
                            fileExecutor.execute {
                                try {
                                    val saved = saveBook(path, name)
                                    runOnUiThread { result.success(saved) }
                                } catch (error: Exception) {
                                    runOnUiThread { result.error("SAVE_FAILED", "Не вдалося зберегти EPUB: ${error.message}", null) }
                                }
                            }
                        }
                    }
                    "open" -> {
                        val uri = call.argument<String>("uri")?.let(Uri::parse)
                        if (uri == null || uri.scheme != "content") {
                            result.error("INVALID_ARGUMENT", "Некоректна адреса EPUB.", null)
                        } else {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "application/epub+zip")
                                    clipData = ClipData.newRawUri("EPUB", uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                startActivity(intent)
                                result.success(null)
                            } catch (_: ActivityNotFoundException) {
                                result.error("NO_READER", "Встановіть додаток для читання EPUB. Книга вже є у Downloads/ranobelib.", null)
                            } catch (error: Exception) {
                                result.error("OPEN_FAILED", "Не вдалося відкрити EPUB: ${error.message}", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveBook(path: String, requestedName: String): Map<String, String> {
        val source = File(path).canonicalFile
        require(source.path.startsWith(cacheDir.canonicalPath + File.separator)) { "Файл поза тимчасовою папкою додатка." }
        require(source.isFile && source.length() > 0) { "EPUB порожній або відсутній." }
        require(requestedName == File(requestedName).name && requestedName.endsWith(".epub")) { "Некоректна назва EPUB." }
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val relativePath = Environment.DIRECTORY_DOWNLOADS + "/ranobelib/"
        // Do not replace existing downloads. MediaStore also resolves collisions
        // with files owned by other apps that are absent from this query.
        val existing = mutableSetOf<String>()
        contentResolver.query(collection, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ?", arrayOf(relativePath), null)?.use { cursor ->
            while (cursor.moveToNext()) existing.add(cursor.getString(0))
        }
        var name = requestedName
        var suffix = 1
        while (existing.contains(name)) name = requestedName.removeSuffix(".epub") + " (${suffix++}).epub"
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/epub+zip")
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(collection, values) ?: error("Android не створив файл у Downloads.")
        try {
            val output = contentResolver.openOutputStream(uri) ?: error("Android не відкрив файл для запису.")
            output.use { stream -> source.inputStream().use { input -> input.copyTo(stream) } }
            val published = contentResolver.update(uri, ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }, null, null)
            check(published > 0) { "Android не опублікував EPUB." }
            contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) name = cursor.getString(0)
            }
            return mapOf("uri" to uri.toString(), "name" to name)
        } catch (error: Exception) {
            contentResolver.delete(uri, null, null)
            throw error
        }
    }

    override fun onDestroy() {
        fileExecutor.shutdown()
        super.onDestroy()
    }
}
