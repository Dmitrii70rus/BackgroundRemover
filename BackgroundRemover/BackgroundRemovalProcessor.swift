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
        guard let normalizedCGImage = normalizedCGImage(from: image) else {
            throw BackgroundRemovalProcessorError.unsupportedImage
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: normalizedCGImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw BackgroundRemovalProcessorError.processingFailed
        }

        guard let observation = request.results?.first else {
            throw BackgroundRemovalProcessorError.noSubjectFound
        }

        let allInstances = observation.allInstances
        guard !allInstances.isEmpty else {
            throw BackgroundRemovalProcessorError.noSubjectFound
        }

        let maskBuffer: CVPixelBuffer
        do {
            maskBuffer = try observation.generateScaledMaskForImage(forInstances: allInstances, from: handler)
        } catch {
            throw BackgroundRemovalProcessorError.processingFailed
        }

        guard let maskCGImage = ciContext.createCGImage(CIImage(cvPixelBuffer: maskBuffer), from: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(maskBuffer), height: CVPixelBufferGetHeight(maskBuffer))) else {
            throw BackgroundRemovalProcessorError.processingFailed
        }

        let cutout = renderTransparentCutout(image: normalizedCGImage, mask: maskCGImage)
        return UIImage(cgImage: cutout, scale: image.scale, orientation: .up)
    }

    private func normalizedCGImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cgImage = image.cgImage {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let normalizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }

        return normalizedImage.cgImage
    }

    private func renderTransparentCutout(image: CGImage, mask: CGImage) -> CGImage {
        let size = CGSize(width: image.width, height: image.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1

        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            context.cgContext.clip(to: rect, mask: mask)
            context.cgContext.draw(image, in: rect)
        }

        return rendered.cgImage ?? image
    }
}
