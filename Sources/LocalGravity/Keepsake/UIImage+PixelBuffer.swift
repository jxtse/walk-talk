//
//  UIImage+PixelBuffer.swift
//  LocalGravity / Keepsake
//
//  P5-T1 — Helper for converting a UIImage into a CVPixelBuffer suitable
//  for AVAssetWriterInputPixelBufferAdaptor.append.
//

#if canImport(UIKit)
import UIKit
import CoreVideo
import CoreImage

public enum PixelBufferError: Error {
    case allocationFailed(CVReturn)
    case ciImageCreationFailed
}

extension UIImage {
    /// Converts this image to a 32BGRA `CVPixelBuffer` of `size`.
    /// The image is drawn into the buffer using a CIContext render so it
    /// composes correctly even when origin/orientation differ.
    public func pixelBuffer(size: CGSize) throws -> CVPixelBuffer {
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width),
                                         Int(size.height),
                                         kCVPixelFormatType_32BGRA,
                                         attrs as CFDictionary,
                                         &pb)
        guard status == kCVReturnSuccess, let buffer = pb else {
            throw PixelBufferError.allocationFailed(status)
        }

        guard let ci = CIImage(image: self) else {
            throw PixelBufferError.ciImageCreationFailed
        }
        // Scale CI image to exactly fit the buffer.
        let sx = size.width / ci.extent.width
        let sy = size.height / ci.extent.height
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        ctx.render(scaled, to: buffer)
        return buffer
    }
}
#endif
