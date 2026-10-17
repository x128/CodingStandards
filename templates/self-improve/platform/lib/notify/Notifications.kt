package lib.notify

class NotificationException(message: String) : RuntimeException(message)

data class Notification(val recipient: String, val text: String)

class Notifications(private val unreachable: Set<String> = emptySet()) {
    private val log = ArrayList<Notification>()

    @Synchronized
    fun post(recipient: String, text: String) {
        if (recipient in unreachable) throw NotificationException("Cannot deliver to $recipient")
        log.add(Notification(recipient, text))
    }

    @get:Synchronized
    val delivered: List<Notification> get() = log.toList()
}
