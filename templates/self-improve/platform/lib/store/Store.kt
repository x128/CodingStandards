package lib.store

import java.io.File
import java.io.IOException
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update

class StoreException(message: String, cause: Throwable? = null) : RuntimeException(message, cause)

data class Row(val id: String, val fields: Map<String, String>)

class Store(private val directory: File, private val broken: Boolean = false) {
    private val tables = HashMap<String, Table>()

    @Synchronized
    fun table(name: String): Table {
        require(name.matches(Regex("[a-z][a-z0-9_]*"))) { "Bad table name: $name" }
        return tables.getOrPut(name) { Table(File(directory, "$name.tbl"), broken) }
    }
}

class Table internal constructor(private val file: File, private val broken: Boolean) {
    private val version = MutableStateFlow(0)
    private val lock = Any()

    fun all(): List<Row> = synchronized(lock) { read() }

    fun find(id: String): Row? = synchronized(lock) { read().firstOrNull { it.id == id } }

    fun put(row: Row) {
        synchronized(lock) {
            val rows = read().toMutableList()
            val index = rows.indexOfFirst { it.id == row.id }
            if (index >= 0) rows[index] = row else rows.add(row)
            write(rows)
        }
        version.update { it + 1 }
    }

    fun delete(id: String) {
        synchronized(lock) { write(read().filterNot { it.id == id }) }
        version.update { it + 1 }
    }

    fun observeAll(): Flow<List<Row>> = version.map { all() }

    private fun read(): List<Row> {
        if (broken) throw StoreException("Cannot read ${file.name}")
        try {
            if (!file.exists()) return emptyList()
            return file.readLines(Charsets.UTF_8).filter { it.isNotEmpty() }.map(::parse)
        } catch (e: IOException) {
            throw StoreException("Cannot read ${file.name}", e)
        }
    }

    private fun write(rows: List<Row>) {
        if (broken) throw StoreException("Cannot write ${file.name}")
        try {
            val directory = file.absoluteFile.parentFile
            if (!directory.isDirectory && !directory.mkdirs()) throw IOException("Cannot create $directory")
            val temporary = File(directory, file.name + ".tmp")
            temporary.writeText(rows.joinToString("") { format(it) + "\n" }, Charsets.UTF_8)
            Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING)
        } catch (e: IOException) {
            throw StoreException("Cannot write ${file.name}", e)
        }
    }

    private fun format(row: Row): String =
        (listOf(encode(row.id)) + row.fields.map { (key, value) -> encode(key) + "=" + encode(value) }).joinToString("\t")

    private fun parse(line: String): Row {
        val parts = line.split("\t")
        val fields = LinkedHashMap<String, String>()
        for (part in parts.drop(1)) {
            val at = part.indexOf('=')
            if (at < 0) throw IOException("Damaged row in ${file.name}")
            fields[decode(part.substring(0, at))] = decode(part.substring(at + 1))
        }
        return Row(decode(parts[0]), fields)
    }

    private fun encode(text: String): String = URLEncoder.encode(text, "UTF-8")

    private fun decode(text: String): String = URLDecoder.decode(text, "UTF-8")
}
