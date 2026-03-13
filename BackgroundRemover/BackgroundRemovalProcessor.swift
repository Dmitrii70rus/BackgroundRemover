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
            return "We couldn't isolate a clear subject in this image. Try a photo with one person or object in the foreground."
        case .processingFailed:
            return "Background removal failed. Please try again."
        }
    }
}

struct BackgroundRemovalProcessor {
    private let ciContext = CIContext(options: nil)
    private let minimumMaskCoverage = 0.01
    private let maximumMaskCoverage = 0.995

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
        foregroundInstanceMask(for: image)
            ?? personSegmentationMask(for: image)
            ?? saliencyMask(for: image, attentionBased: true)
            ?? saliencyMask(for: image, attentionBased: false)
    }

    private func foregroundInstanceMask(for image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        request.usesCPUOnly = true
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
            return makeValidatedMask(from: maskBuffer)
        } catch {
            return nil
        }
    }

    private func personSegmentationMask(for image: CGImage) -> CGImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        request.usesCPUOnly = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            guard let result = request.results?.first else {
                return nil
            }

            return makeValidatedMask(from: result.pixelBuffer)
        } catch {
            return nil
        }
    }

    private func saliencyMask(for image: CGImage, attentionBased: Bool) -> CGImage? {
        let request: VNImageBasedRequest = attentionBased
            ? VNGenerateAttentionBasedSaliencyImageRequest()
            : VNGenerateObjectnessBasedSaliencyImageRequest()
        request.usesCPUOnly = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
            let observation: VNSaliencyImageObservation?
            if attentionBased {
                observation = (request as? VNGenerateAttentionBasedSaliencyImageRequest)?.results?.first
            } else {
                observation = (request as? VNGenerateObjectnessBasedSaliencyImageRequest)?.results?.first
            }

            guard let pixelBuffer = observation?.pixelBuffer else {
                return nil
            }

            return makeValidatedMask(from: pixelBuffer)
        } catch {
            return nil
        }
    }

    private func makeValidatedMask(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let extent = CGRect(
            x: 0,
            y: 0,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        let ciMask = CIImage(cvPixelBuffer: pixelBuffer)
        let normalizedMask = normalizeMask(ciMask).cropped(to: extent)

        guard let mask = ciContext.createCGImage(normalizedMask, from: extent),
              hasUsableCoverage(mask) else {
            return nil
        }

        return mask
    }

    private func normalizeMask(_ mask: CIImage) -> CIImage {
        guard let controls = CIFilter(name: "CIColorControls") else {
            return mask
        }

        controls.setValue(mask, forKey: kCIInputImageKey)
        controls.setValue(1.0, forKey: kCIInputSaturationKey)
        controls.setValue(0.0, forKey: kCIInputBrightnessKey)
        controls.setValue(1.25, forKey: kCIInputContrastKey)

        return controls.outputImage ?? mask
    }

    private func hasUsableCoverage(_ mask: CGImage) -> Bool {
        let ciMask = CIImage(cgImage: mask)
        guard let avgFilter = CIFilter(name: "CIAreaAverage") else {
            return true
        }

        avgFilter.setValue(ciMask, forKey: kCIInputImageKey)
        avgFilter.setValue(CIVector(cgRect: ciMask.extent), forKey: kCIInputExtentKey)

        guard let output = avgFilter.outputImage else {
            return true
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let coverage = Double(pixel[0]) / 255.0
        return coverage >= minimumMaskCoverage && coverage <= maximumMaskCoverage
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
