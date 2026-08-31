import SwiftUI

/// The circular key-photo treatment used everywhere in the app (the fan
/// ring, key rows, the detail header): a color-tinted circle with the photo
/// filled in, or the category glyph as a placeholder -- tinted to the key's
/// category so the list reads at a glance even before every key has a photo.
struct KeyPhotoView: View {
    let photoData: Data?
    var symbolName: String = "key.fill"
    var tintColor: Color = KRTheme.brass
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle()
                .fill(tintColor.opacity(0.16))
                .frame(width: size, height: size)
            if let photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size - 6, height: size - 6)
                    .clipShape(Circle())
            } else {
                Image(systemName: symbolName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.5, height: size * 0.5)
                    .foregroundStyle(tintColor)
            }
        }
        .overlay(Circle().stroke(tintColor.opacity(0.35), lineWidth: 1))
    }
}
