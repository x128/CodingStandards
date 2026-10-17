package tools.runner

import kotlin.system.exitProcess
import org.junit.internal.TextListener
import org.junit.runner.Description
import org.junit.runner.JUnitCore
import org.junit.runner.notification.RunListener

private const val LIMIT_SECONDS = 60L

private class Watch : RunListener() {
    @Volatile var current: String? = null
    @Volatile var startedAt: Long = 0

    override fun testStarted(description: Description) {
        current = "${description.className}.${description.methodName}"
        startedAt = System.nanoTime()
    }

    override fun testFinished(description: Description) {
        current = null
    }
}

fun main(arguments: Array<String>) {
    val classes = arguments.map { Class.forName(it) }
    val watch = Watch()
    val watchdog = Thread {
        while (true) {
            Thread.sleep(1000)
            val name = watch.current ?: continue
            if ((System.nanoTime() - watch.startedAt) / 1_000_000_000 >= LIMIT_SECONDS) {
                System.out.println("\nTEST HANGS (more than $LIMIT_SECONDS s): $name")
                System.out.println("A test must end: cancel what it started (for a ViewModel, call clear()).")
                System.out.flush()
                Runtime.getRuntime().halt(3)
            }
        }
    }
    watchdog.isDaemon = true
    watchdog.start()
    val core = JUnitCore()
    core.addListener(TextListener(System.out))
    core.addListener(watch)
    val result = core.run(*classes.toTypedArray())
    exitProcess(if (result.wasSuccessful()) 0 else 1)
}
