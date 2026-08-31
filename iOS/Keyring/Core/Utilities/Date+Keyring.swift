import Foundation

extension Date {
    /// "Today at 18:42", "Yesterday", or "Aug 26" — matches the product spec's
    /// location/history examples.
    var keyringRelativeDescription: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return "Today at \(self.formatted(date: .omitted, time: .shortened))"
        } else if calendar.isDateInYesterday(self) {
            return "Yesterday"
        } else {
            return self.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}
