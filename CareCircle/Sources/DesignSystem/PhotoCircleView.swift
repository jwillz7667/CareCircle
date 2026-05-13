import PhotosUI
import SwiftUI

// MARK: - PhotoCircleView

struct PhotoCircleView: View {
    let imageData: Data?
    var diameter: CGFloat = 96
    var isEditable = false
    var selection: Binding<PhotosPickerItem?>?

    var body: some View {
        if isEditable, let selection {
            PhotosPicker(selection: selection, matching: .images, photoLibrary: .shared()) {
                avatar
                    .overlay(alignment: .bottomTrailing) {
                        editBadge
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Care Recipient photo")
            .accessibilityHint("Choose a new photo from your library.")
            .accessibilityAddTraits(.isButton)
        } else {
            avatar
                .accessibilityLabel("Care Recipient photo")
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: diameter, height: diameter)
                .clipShape(.circle)
        } else {
            ZStack {
                Color.ccSurface
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: diameter * 0.7, weight: .light))
                    .foregroundStyle(Color.ccPrimary.opacity(0.6))
            }
            .frame(width: diameter, height: diameter)
            .clipShape(.circle)
        }
    }

    private var editBadge: some View {
        Image(systemName: "camera.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(8)
            .background(Color.ccPrimary)
            .clipShape(.circle)
            .overlay {
                SwiftUI.Circle()
                    .stroke(Color.ccBackground, lineWidth: 2)
            }
    }
}
