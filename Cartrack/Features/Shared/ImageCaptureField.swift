import SwiftUI
import UIKit

struct ImageCaptureField: View {
    let title: String
    let caption: String
    @Binding var existingPath: String?
    @Binding var image: UIImage?

    @State private var isShowingPicker = false
    @State private var sourceType: UIImagePickerController.SourceType = .photoLibrary

    var body: some View {
        Section(title) {
            preview

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button("Camara") {
                    sourceType = .camera
                    isShowingPicker = true
                }
                .buttonStyle(.borderedProminent)

                Button("Fotos") {
                    sourceType = .photoLibrary
                    isShowingPicker = true
                }
                .buttonStyle(.bordered)

                if image != nil || existingPath != nil {
                    Button("Quitar", role: .destructive) {
                        image = nil
                        existingPath = nil
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingPicker) {
            ImagePickerView(image: $image, sourceType: sourceType)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if let existingPath, let uiImage = ImageStorageService.shared.loadImage(at: existingPath) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 140)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Sin imagen")
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }
}
