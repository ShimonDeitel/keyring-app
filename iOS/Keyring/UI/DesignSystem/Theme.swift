import SwiftUI

/// Keyring's identity: a warm graphite/brass hardware aesthetic (like a
/// hook by the front door), distinct from every sibling app's palette.
enum KRTheme {
    static let backdrop = Color(red: 0.945, green: 0.937, blue: 0.918)  // warm bone
    static let surface = Color.white
    static let surfaceRaised = Color(red: 0.882, green: 0.867, blue: 0.831)
    static let ink = Color(red: 0.180, green: 0.161, blue: 0.129)
    static let inkFaded = Color(red: 0.180, green: 0.161, blue: 0.129).opacity(0.56)
    static let rule = Color.black.opacity(0.09)

    static let brass = Color(red: 0.714, green: 0.573, blue: 0.267)
    static let brassBright = Color(red: 0.812, green: 0.663, blue: 0.337)
    static let forest = Color(red: 0.294, green: 0.373, blue: 0.298)
    static let danger = Color(red: 0.729, green: 0.290, blue: 0.243)

    static let titleFont = Font.system(.title2, design: .rounded).weight(.bold)
    static let headlineFont = Font.system(.headline, design: .rounded).weight(.semibold)

    // Status colors for loan/spare/lost badges, added for Phase 2.
    static let loanedColor = brassBright
    static let lostColor = danger
    static let spareColor = Color(red: 0.318, green: 0.451, blue: 0.573)

    static let cardCorner: CGFloat = 16
    static let smallCorner: CGFloat = 10

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }
}

struct DismissKeyboardOnTap: ViewModifier {
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
        )
    }
}

extension View {
    func dismissKeyboardOnTap() -> some View {
        modifier(DismissKeyboardOnTap())
    }
}
