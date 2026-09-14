import Foundation
import UserNotifications

/// Schedules a local reminder for a key's expected loan-return date. The
/// loan sheet has offered a "reminder date" toggle since Phase 1 with
/// nothing behind it -- this is what actually fires the reminder. Called by
/// `SwiftDataKeyRepository` alongside SpotlightIndexer, on the same
/// create/update/delete lifecycle. Permission is requested lazily, only
/// when a reminder is actually needed, matching LocationProvider's style.
enum LoanReminderService {
    static func schedule(for key: KeyEntity) {
        guard let returnDate = key.expectedReturnDate else {
            cancel(for: key)
            return
        }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: returnDate)
        components.hour = 10
        guard let fireDate = Calendar.current.date(from: components), fireDate > .now else {
            cancel(for: key)
            return
        }

        let center = UNUserNotificationCenter.current()
        let keyID = key.id.uuidString
        let keyName = key.name
        let person = (key.loanedTo?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "someone"

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(keyName) is due back"
            content.body = "Loaned to \(person) -- check if it's back yet."
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: identifier(forKeyID: keyID), content: content, trigger: trigger)
            center.add(request)
        }
    }

    static func cancel(for key: KeyEntity) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(forKeyID: key.id.uuidString)])
    }

    private static func identifier(forKeyID keyID: String) -> String {
        "keyring.loanReminder.\(keyID)"
    }
}
