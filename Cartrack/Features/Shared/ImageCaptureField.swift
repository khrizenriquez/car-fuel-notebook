import PhotosUI
import SwiftUI
import UIKit

struct ImageCaptureField: View {
    let title: String
    let caption: String
    @Binding var existingPath: String?
    @Binding var image: UIImage?

    @State private var isShowingPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        Section(title) {
            preview

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button("Camara") {
                    isShowingPicker = true
                }
                .buttonStyle(.borderedProminent)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Text("Fotos")
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
            ImagePickerView(image: $image, sourceType: .camera)
        }
        .task(id: selectedPhotoItem) {
            await loadSelectedPhoto()
        }
    }

    @MainActor
    private func loadSelectedPhoto() async {
        guard let selectedPhotoItem else { return }
        do {
            if let data = try await selectedPhotoItem.loadTransferable(type: Data.self),
               let selectedImage = UIImage(data: data) {
                image = selectedImage
                existingPath = nil
            }
        } catch {
            // Keep the previous image if Photos fails to deliver data.
        }
        self.selectedPhotoItem = nil
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
