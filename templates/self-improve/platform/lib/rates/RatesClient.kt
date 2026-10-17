package lib.rates

import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeParseException

class RatesException(message: String, cause: Throwable? = null) : RuntimeException(message, cause)

class RatesClient(private val baseUrl: String) {

    fun eurRatesOn(date: String): Map<String, String> {
        val day = try {
            LocalDate.parse(date)
        } catch (e: DateTimeParseException) {
            throw IllegalArgumentException("Not a date: $date", e)
        }
        if (baseUrl != DEMO_URL) throw RatesException("Cannot reach $baseUrl")
        if (day.dayOfWeek == DayOfWeek.SATURDAY || day.dayOfWeek == DayOfWeek.SUNDAY) return emptyMap()
        return DEMO_RATES
    }

    companion object {
        const val DEMO_URL = "demo://rates"

        private val DEMO_RATES = linkedMapOf(
            "USD" to "1.10",
            "GBP" to "0.85",
            "CHF" to "0.95",
            "PLN" to "4.30",
            "CZK" to "25.00",
            "SEK" to "11.20",
            "NOK" to "11.60"
        )
    }
}
