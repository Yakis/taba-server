/// Formats minutes after midnight for messages, such as "16:25".
enum Clock {
    /// "HH:MM", wrapping past 24:00 so that an after-midnight end shows as, for example, "00:30".
    static func text(_ minutes: Int) -> String {
        let wrapped = ((minutes % 1440) + 1440) % 1440
        return FixedWidthNumber.format(wrapped / 60, width: 2) + ":" + FixedWidthNumber.format(wrapped % 60, width: 2)
    }
}
