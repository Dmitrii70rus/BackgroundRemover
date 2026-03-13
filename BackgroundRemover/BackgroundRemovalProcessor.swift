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

        guard let mask = makeSubjectMask(for: normalizedCGImage) else {
            throw BackgroundRemovalProcessorError.noSubjectFound
        }

        let cutout = renderTransparentCutout(image: normalizedCGImage, mask: mask)
        return UIImage(cgImage: cutout, scale: image.scale, orientation: .up)
    }

    private func makeSubjectMask(for image: CGImage) -> CGImage? {
        if let visionMask = visionMask(for: image) {
            return visionMask
        }

        return personSegmentationMask(for: image)
    }

    private func visionMask(for image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                return nil
            }

            let allInstances = observation.allInstances
            guard !allInstances.isEmpty else {
                return nil
            }

            let maskBuffer = try observation.generateScaledMaskForImage(forInstances: allInstances, from: handler)
            let maskExtent = CGRect(
                x: 0,
                y: 0,
                width: CVPixelBufferGetWidth(maskBuffer),
                height: CVPixelBufferGetHeight(maskBuffer)
            )

            return ciContext.createCGImage(CIImage(cvPixelBuffer: maskBuffer), from: maskExtent)
        } catch {
            return nil
        }
    }

    private func personSegmentationMask(for image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)

        guard let filter = CIFilter(name: "CIPersonSegmentation") else {
            return nil
        }

        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(1, forKey: "inputQualityLevel")

        guard var mask = filter.outputImage else {
            return nil
        }

        if mask.extent.size != input.extent.size {
            let scaleX = input.extent.width / mask.extent.width
            let scaleY = input.extent.height / mask.extent.height
            mask = mask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        }

        mask = mask.cropped(to: input.extent)

        return ciContext.createCGImage(mask, from: input.extent)
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
