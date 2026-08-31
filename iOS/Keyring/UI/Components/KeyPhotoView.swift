import SwiftUI

/// The circular key-photo treatment used everywhere in the app (the fan
/// ring, key rows, the detail header): a brass-ringed circle with the photo
/// filled in, or the category glyph as a placeholder.
struct KeyPhotoView: View {
    let photoData: Data?
    var symbolName: String = "key.fill"
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle()
                .fill(KRTheme.surfaceRaised)
                .frame(width: size, height: size)
            if let photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size - 6, height: size - 6)
                    .clipShape(Circle())
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.36))
                    .foregroundStyle(KRTheme.brass)
            }
        }
        .overlay(Circle().stroke(KRTheme.rule, lineWidth: 1))
    }
}
