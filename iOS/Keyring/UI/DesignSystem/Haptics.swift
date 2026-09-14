import UIKit

/// Tasteful haptic touches for the app's signature moments -- the fan-ring
/// reveal, successful saves, and loan state changes. Absent before; a tap
/// gesture with a spring animation and no haptic reads as flat on a real
/// device even when the animation itself is good.
enum Haptics {
    static func fanRingToggle() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func lightTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
