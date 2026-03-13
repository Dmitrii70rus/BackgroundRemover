import Foundation
import Combine
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BackgroundRemoverViewModel: ObservableObject {
    enum CompareMode: String, CaseIterable, Identifiable {
        case original = "Original"
        case cutout = "Cutout"

        var id: String { rawValue }
    }

    @Published var selectedPhotoItem: PhotosPickerItem?
    @Published var selectedImage: UIImage?
    @Published var processedImage: UIImage?
    @Published var compareMode: CompareMode = .cutout
    @Published var isProcessing = false
    @Published var statusMessage: String?
    @Published var showPaywall = false
    @Published var sharePNGData: Data?
    @Published var errorMessage: String?

    private let processor = BackgroundRemovalProcessor()

    func loadSelectedPhoto() async {
        guard let selectedPhotoItem else { return }

        do {
            guard let data = try await selectedPhotoItem.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw BackgroundRemovalProcessorError.unsupportedImage
            }
            self.selectedImage = image
            self.processedImage = nil
            self.sharePNGData = nil
            self.statusMessage = nil
            self.errorMessage = nil
            self.compareMode = .original
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeBackground(using purchaseManager: PurchaseManager) async {
        guard let selectedImage else {
            errorMessage = "Select a photo first."
            return
        }

        guard purchaseManager.canUseFreeRemoval else {
            showPaywall = true
            return
        }

        isProcessing = true
        statusMessage = nil
        errorMessage = nil

        defer { isProcessing = false }

        do {
            let output = try processor.removeBackground(from: selectedImage)
            processedImage = output
            compareMode = .cutout
            sharePNGData = output.pngData()
            purchaseManager.consumeFreeUseIfNeeded()
            statusMessage = "Background removed successfully."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveResult() async {
        guard let pngData = sharePNGData else {
            errorMessage = "No processed image to save."
            return
        }

        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .denied || status == .restricted {
            errorMessage = "Photo Library access denied. Enable access in Settings to save images."
            return
        }

        if status == .notDetermined {
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
            if !granted {
                errorMessage = "Photo Library permission is required to save your cutout."
                return
            }
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = UTType.png.identifier
                request.addResource(with: .photo, data: pngData, options: options)
            }
            statusMessage = "Saved as PNG to your Photo Library."
        } catch {
            errorMessage = "Couldn't save image. Please try again."
        }
    }
}

struct PNGShareItem: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.data
        }
    }
}
