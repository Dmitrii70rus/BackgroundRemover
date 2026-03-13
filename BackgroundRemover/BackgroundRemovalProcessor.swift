import CoreImage
import UIKit
import Vision

enum BackgroundRemovalProcessorError: LocalizedError {
    case unsupportedImage
    case noSubjectFound
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            return "This image format is not supported for background removal."
        case .noSubjectFound:
            return "We couldn't find a clear subject in this photo. Try another image."
        case .processingFailed:
            return "Background removal failed. Please try again."
        }
    }
}

struct BackgroundRemovalProcessor {
    private let ciContext = CIContext(options: nil)

    func removeBackground(from image: UIImage) throws -> UIImage {
        guard let inputCIImage = CIImage(image: image) else {
            throw BackgroundRemovalProcessorError.unsupportedImage
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: inputCIImage)

        do {
            try handler.perform([request])
        } catch {
            throw BackgroundRemovalProcessorError.processingFailed
        }

        guard let observation = request.results?.first else {
            throw BackgroundRemovalProcessorError.noSubjectFound
        }

        let allInstances = IndexSet(integersIn: 1...observation.instanceCount)
        if allInstances.isEmpty {
            throw BackgroundRemovalProcessorError.noSubjectFound
        }

        let maskBuffer: CVPixelBuffer
        do {
            maskBuffer = try observation.generateScaledMaskForImage(forInstances: allInstances, from: handler)
        } catch {
            throw BackgroundRemovalProcessorError.processingFailed
        }

        let maskImage = CIImage(cvPixelBuffer: maskBuffer)
        let transparentBackground = CIImage(color: .clear).cropped(to: inputCIImage.extent)

        guard let blend = CIFilter(
            name: "CIBlendWithMask",
            parameters: [
                kCIInputImageKey: inputCIImage,
                kCIInputBackgroundImageKey: transparentBackground,
                kCIInputMaskImageKey: maskImage
            ]
        )?.outputImage,
              let cgImage = ciContext.createCGImage(blend, from: inputCIImage.extent) else {
            throw BackgroundRemovalProcessorError.processingFailed
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
