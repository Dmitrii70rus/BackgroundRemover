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

    // Keep validation permissive enough for close-up portraits and tall selfies.
    private let minimumMaskCoverage = 0.003
    private let maximumMaskCoverage = 0.9995

    func removeBackground(from image: UIImage) throws -> UIImage {
        let input = try validatedInput(from: image)

        guard let subjectMask = extractSubjectMask(
            cgImage: input.cgImage,
            orientation: input.orientation
        ) else {
            throw BackgroundRemovalProcessorError.noSubjectFound
        }

        guard let cutout = compositeCutout(
            image: input.cgImage,
            mask: subjectMask
        ) else {
            throw BackgroundRemovalProcessorError.processingFailed
        }

        return UIImage(cgImage: cutout, scale: image.scale, orientation: .up)
    }

    // MARK: - Input

    private func validatedInput(from image: UIImage) throws -> (cgImage: CGImage, orientation: CGImagePropertyOrientation) {
        if let cgImage = image.cgImage {
            return (cgImage, CGImagePropertyOrientation(image.imageOrientation))
        }

        if let ciImage = image.ciImage,
           let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            return (cgImage, CGImagePropertyOrientation(image.imageOrientation))
        }

        throw BackgroundRemovalProcessorError.unsupportedImage
    }

    // MARK: - Subject extraction

    private func extractSubjectMask(cgImage: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        foregroundInstanceMask(cgImage: cgImage, orientation: orientation)
            ?? personSegmentationMask(cgImage: cgImage, orientation: orientation)
            ?? saliencyMask(cgImage: cgImage, orientation: orientation, attentionBased: true)
            ?? saliencyMask(cgImage: cgImage, orientation: orientation, attentionBased: false)
    }

    private func foregroundInstanceMask(cgImage: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }

            let instances = observation.allInstances
            guard !instances.isEmpty else { return nil }

            let maskBuffer = try observation.generateScaledMaskForImage(forInstances: instances, from: handler)
            return validatedMask(
                from: maskBuffer,
                targetWidth: cgImage.width,
                targetHeight: cgImage.height
            )
        } catch {
            return nil
        }
    }

    private func personSegmentationMask(cgImage: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
            guard let result = request.results?.first else { return nil }

            return validatedMask(
                from: result.pixelBuffer,
                targetWidth: cgImage.width,
                targetHeight: cgImage.height
            )
        } catch {
            return nil
        }
    }

    private func saliencyMask(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        attentionBased: Bool
    ) -> CGImage? {
        let request: VNImageBasedRequest = attentionBased
            ? VNGenerateAttentionBasedSaliencyImageRequest()
            : VNGenerateObjectnessBasedSaliencyImageRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
            let observation: VNSaliencyImageObservation?
            if attentionBased {
                observation = (request as? VNGenerateAttentionBasedSaliencyImageRequest)?.results?.first
            } else {
                observation = (request as? VNGenerateObjectnessBasedSaliencyImageRequest)?.results?.first
            }

            guard let pixelBuffer = observation?.pixelBuffer else { return nil }

            return validatedMask(
                from: pixelBuffer,
                targetWidth: cgImage.width,
                targetHeight: cgImage.height
            )
        } catch {
            return nil
        }
    }

    // MARK: - Mask processing

    private func validatedMask(from pixelBuffer: CVPixelBuffer, targetWidth: Int, targetHeight: Int) -> CGImage? {
        let maskImage = CIImage(cvPixelBuffer: pixelBuffer)
        let maskExtent = maskImage.extent

        guard maskExtent.width > 0, maskExtent.height > 0 else {
            return nil
        }

        let scaledMask = maskImage.transformed(
            by: CGAffineTransform(
                scaleX: CGFloat(targetWidth) / maskExtent.width,
                y: CGFloat(targetHeight) / maskExtent.height
            )
        )
        .cropped(to: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        let preparedMask = normalizedMask(scaledMask)

        guard let maskCGImage = ciContext.createCGImage(
            preparedMask,
            from: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        ), hasUsableCoverage(maskCGImage) else {
            return nil
        }

        return maskCGImage
    }

    private func normalizedMask(_ mask: CIImage) -> CIImage {
        guard let controls = CIFilter(name: "CIColorControls") else {
            return mask
        }

        controls.setValue(mask, forKey: kCIInputImageKey)
        controls.setValue(1.0, forKey: kCIInputSaturationKey)
        controls.setValue(0.0, forKey: kCIInputBrightnessKey)
        controls.setValue(1.2, forKey: kCIInputContrastKey)

        return controls.outputImage ?? mask
    }

    private func hasUsableCoverage(_ mask: CGImage) -> Bool {
        let ciMask = CIImage(cgImage: mask)
        guard let areaAverage = CIFilter(name: "CIAreaAverage") else {
            return true
        }

        areaAverage.setValue(ciMask, forKey: kCIInputImageKey)
        areaAverage.setValue(CIVector(cgRect: ciMask.extent), forKey: kCIInputExtentKey)

        guard let output = areaAverage.outputImage else {
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

    // MARK: - Compositing

    private func compositeCutout(image: CGImage, mask: CGImage) -> CGImage? {
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

        return rendered.cgImage
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .down:
            self = .down
        case .left:
            self = .left
        case .right:
            self = .right
        case .upMirrored:
            self = .upMirrored
        case .downMirrored:
            self = .downMirrored
        case .leftMirrored:
            self = .leftMirrored
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
