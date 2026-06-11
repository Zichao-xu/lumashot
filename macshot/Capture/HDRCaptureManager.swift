import AppKit
import CoreImage
import Foundation
import ImageIO
import ScreenCaptureKit

/// Handles the explicit HDR screenshot path. Normal screenshots do not use this file.
enum HDRCaptureManager {
    typealias SaveCompletion = (URL?) -> Void

    static func saveHDRScreenshot(
        screen: NSScreen,
        rect: NSRect,
        showsCursor: Bool,
        annotationOverlay: CGImage? = nil,
        outputURL requestedOutputURL: URL? = nil,
        completion: @escaping SaveCompletion
    ) {
        Task {
            guard #available(macOS 15.0, *) else {
                await MainActor.run { completion(nil) }
                return
            }

            do {
                guard rect.width > 1, rect.height > 1 else {
                    await MainActor.run { completion(nil) }
                    return
                }

                let hdrCGImage = try await captureHDRImage(
                    screen: screen,
                    rect: rect,
                    showsCursor: showsCursor
                )
                // Burn the user's annotations into the freshly captured HDR
                // pixels. ScreenCaptureKit re-grabs the screen and never sees the
                // overlay-drawn marks, so without this they'd be lost in HDR mode.
                let hdrImage = compositeAnnotationOverlay(
                    annotationOverlay,
                    onto: CIImage(cgImage: hdrCGImage)
                )
                let outputURL = try writeAppleGainMapHEIC(
                    from: hdrImage,
                    outputURL: requestedOutputURL
                )
                await MainActor.run { completion(outputURL) }
            } catch {
                #if DEBUG
                    NSLog("Lumashot: HDR gain map capture failed: \(error.localizedDescription)")
                #endif
                await MainActor.run { completion(nil) }
            }
        }
    }

    @available(macOS 15.0, *)
    static var isHDRCaptureSupported: Bool {
        true
    }

    @available(macOS 15.0, *)
    private static func captureHDRImage(
        screen: NSScreen,
        rect: NSRect,
        showsCursor: Bool
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        )
        guard let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let display = content.displays.first(where: { $0.displayID == screenID }) else {
            throw HDRCaptureError.displayNotFound
        }

        let localRect = CGRect(
            x: rect.origin.x - screen.frame.origin.x,
            // AppKit: bottom-left origin, Y increases upward.
            // SCK:     top-left origin, Y increases downward.
            // Flip Y so the HDR capture aligns with what the user selected.
            y: screen.frame.height - (rect.origin.y - screen.frame.origin.y) - rect.height,
            width: rect.width,
            height: rect.height
        )
        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration(preset: .captureHDRScreenshotLocalDisplay)
        config.sourceRect = localRect
        config.width = max(1, Int(rect.width * scale))
        config.height = max(1, Int(rect.height * scale))
        config.showsCursor = showsCursor
        config.captureResolution = .best

        let filter = SCContentFilter(display: display, excludingWindows: [])
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    }

    /// Burn the annotation overlay (a transparent SDR layer rendered by the
    /// overlay view at the selection's native pixels) into the HDR image using
    /// linear-light source-over compositing. Where the overlay's alpha is 0 the
    /// base HDR pixels pass through untouched, so HDR highlights (values > 1.0)
    /// are preserved; annotation marks sit on top as opaque SDR-range pixels.
    /// Returns the base unchanged when there is no overlay.
    private static func compositeAnnotationOverlay(
        _ overlay: CGImage?,
        onto base: CIImage
    ) -> CIImage {
        guard let overlay else { return base }
        var layer = CIImage(cgImage: overlay)
        // Match the overlay to the HDR image's pixel extent (absorbs ±1px
        // rounding between the SCK capture size and the rendered overlay size).
        if layer.extent.width > 0, layer.extent.height > 0,
            layer.extent.width != base.extent.width
                || layer.extent.height != base.extent.height
        {
            layer = layer.transformed(by: CGAffineTransform(
                scaleX: base.extent.width / layer.extent.width,
                y: base.extent.height / layer.extent.height
            ))
        }
        // Align origins so the overlay sits exactly over the base.
        layer = layer.transformed(by: CGAffineTransform(
            translationX: base.extent.minX - layer.extent.minX,
            y: base.extent.minY - layer.extent.minY
        ))
        // HDR "ink": make annotation marks vivid and bright enough to glow on an
        // HDR display instead of reading as dull SDR next to bright HDR content.
        // Saturation is boosted first, then luminance is multiplied in Core
        // Image's linear working space (annotationHDRGain is a true brightness
        // factor; ~6x sits near the Apple gain-map headroom ceiling). The
        // transparent background (alpha 0) is untouched — only the marks change.
        if annotationHDRSaturation != 1.0 {
            layer = layer.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: annotationHDRSaturation
            ])
        }
        if annotationHDRGain != 1.0 {
            let g = CGFloat(annotationHDRGain)
            layer = layer.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: g, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: g, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        }
        return layer.composited(over: base)
            .cropped(to: base.extent)
            .settingProperties(base.properties)
    }

    /// Linear-light brightness multiplier applied to annotation marks in HDR
    /// output so they glow rather than read as dull SDR ink. 6.0 ≈ +2.6 stops,
    /// near the Apple gain-map headroom ceiling (`maxAppleHeadroom`).
    private static let annotationHDRGain: Float = 6.0

    /// Saturation multiplier for annotation marks in HDR output, so the colors
    /// read as vivid rather than washed out once brightened. 1.0 = unchanged.
    private static let annotationHDRSaturation: Float = 1.4

    @available(macOS 15.0, *)
    private static func writeAppleGainMapHEIC(
        from hdrImage: CIImage,
        outputURL requestedOutputURL: URL? = nil
    ) throws -> URL {
        let products = try makeToGainMapHDRProducts(from: hdrImage)
        let imageWithProperties = applyMakerAppleProperties(
            to: products.sdrImage,
            using: products.hdrImage,
            maxHeadroom: products.gainMapHeadroom
        )

        let fileURL: URL
        if let requestedOutputURL {
            fileURL = requestedOutputURL
        } else {
            let dirURL = ImageEncoder.clipboardTmpDirectory
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            fileURL = try makeUniqueClipboardHEICURL(in: dirURL)
        }
        let options: [CIImageRepresentationOption: Any] = [
            .hdrGainMapImage: products.gainMapImage,
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): imageQuality
        ]

        try products.context.writeHEIFRepresentation(
            of: imageWithProperties,
            to: fileURL,
            format: .RGBA8,
            colorSpace: products.outputColorSpace,
            options: options
        )
        #if DEBUG
            NSLog(
                "Lumashot: HDR gain map headroom full=\(products.fullHeadroom) toneMap=\(products.toneMapHeadroom) gainMap=\(products.gainMapHeadroom)"
            )
        #endif
        return fileURL
    }

    private static func makeUniqueClipboardHEICURL(in directory: URL) throws -> URL {
        let filename = FilenameFormatter.defaultImageFilename(fileExtension: "heic")
        let baseName = (filename as NSString).deletingPathExtension
        var fileURL = directory.appendingPathComponent(filename)
        var counter = 2

        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = directory.appendingPathComponent("\(baseName) (\(counter)).heic")
            counter += 1
            if counter > 1000 {
                throw HDRCaptureError.outputCollision
            }
        }

        return fileURL
    }

    @available(macOS 15.0, *)
    private struct GainMapProducts {
        let hdrImage: CIImage
        let sdrImage: CIImage
        let gainMapImage: CIImage
        let context: CIContext
        let outputColorSpace: CGColorSpace
        let fullHeadroom: Float
        let toneMapHeadroom: Float
        let gainMapHeadroom: Float
    }

    @available(macOS 15.0, *)
    private static func makeToGainMapHDRProducts(from hdrImage: CIImage) throws -> GainMapProducts {
        let context = CIContext()
        let outputColorSpace = outputColorSpaceMatchingToGainMapHDR(for: hdrImage)
        let fullHeadroom = measureHeadroom(in: hdrImage, context: context, colorSpace: nil)

        let scaledForToneMap = hdrImage.transformed(
            by: CGAffineTransform(
                scaleX: 1.0 / toneMappingRatio,
                y: 1.0 / toneMappingRatio
            )
        )
        var toneMapHeadroom = measureHeadroom(
            in: scaledForToneMap,
            context: context,
            colorSpace: nil
        )

        if fullHeadroom < 1.05 {
            toneMapHeadroom = 1.0
        }
        if toneMapHeadroom < 1.0 {
            toneMapHeadroom = 1.0
        }
        if toneMapHeadroom > maxAppleHeadroom {
            toneMapHeadroom = maxAppleHeadroom
        }

        let gainMapHeadroom = max(1.01, min(maxAppleHeadroom, fullHeadroom))
        let sdrImage = hdrImage.applyingFilter("CIToneMapHeadroom", parameters: [
            "inputSourceHeadroom": toneMapHeadroom,
            "inputTargetHeadroom": 1.0
        ])
        let gainMapImage = try makeGainMap(
            hdrImage: hdrImage,
            sdrImage: sdrImage,
            maxHeadroom: gainMapHeadroom
        )

        return GainMapProducts(
            hdrImage: hdrImage,
            sdrImage: sdrImage,
            gainMapImage: gainMapImage,
            context: context,
            outputColorSpace: outputColorSpace,
            fullHeadroom: fullHeadroom,
            toneMapHeadroom: toneMapHeadroom,
            gainMapHeadroom: gainMapHeadroom
        )
    }

    @available(macOS 15.0, *)
    private static func measureHeadroom(
        in image: CIImage,
        context: CIContext,
        colorSpace: CGColorSpace?
    ) -> Float {
        let extent = CIVector(cgRect: image.extent)
        guard let areaMaximum = CIFilter(
            name: "CIAreaMaximum",
            parameters: [
                kCIInputImageKey: image,
                kCIInputExtentKey: extent
            ]
        )?.outputImage else {
            return fallbackSourceHeadroom
        }

        var rgba = [Float](repeating: 0, count: 4)
        context.render(
            areaMaximum,
            toBitmap: &rgba,
            rowBytes: MemoryLayout<Float>.size * 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBAf,
            colorSpace: colorSpace
        )

        let maxChannel = max(rgba[0], max(rgba[1], rgba[2]))
        if maxChannel.isFinite, maxChannel > 1.0 {
            return maxChannel
        }
        return 1.0
    }

    private static func outputColorSpaceMatchingToGainMapHDR(for image: CIImage) -> CGColorSpace {
        let colorSpaceDescription = String(describing: image.colorSpace)
        if colorSpaceDescription.contains("709") || colorSpaceDescription.contains("sRGB") {
            return CGColorSpace(name: CGColorSpace.itur_709)
                ?? CGColorSpace(name: CGColorSpace.sRGB)!
        }
        if colorSpaceDescription.contains("2100") || colorSpaceDescription.contains("2020") {
            return CGColorSpace(name: CGColorSpace.itur_2020_sRGBGamma)
                ?? CGColorSpace(name: CGColorSpace.displayP3)!
        }
        return CGColorSpace(name: CGColorSpace.displayP3)
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
    }

    @available(macOS 15.0, *)
    private static func makeGainMap(
        hdrImage: CIImage,
        sdrImage: CIImage,
        maxHeadroom: Float
    ) throws -> CIImage {
        let filter = HDRGainMapFilter()
        filter.hdrImage = hdrImage
        filter.sdrImage = sdrImage
        filter.maxHeadroom = maxHeadroom
        guard let outputImage = filter.outputImage else {
            throw HDRCaptureError.gainMapFailed
        }
        return outputImage
    }

    private static func applyMakerAppleProperties(
        to sdrImage: CIImage,
        using hdrImage: CIImage,
        maxHeadroom: Float
    ) -> CIImage {
        let stops = log2(maxHeadroom)
        var imageProperties = hdrImage.properties
        var makerApple = imageProperties[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] ?? [:]

        switch stops {
        case let value where value >= 2.3:
            makerApple["33"] = 1.0
            makerApple["48"] = (3.0 - stops) / 70.0
        case 1.8..<2.3:
            makerApple["33"] = 1.0
            makerApple["48"] = (2.30303 - stops) / 0.303
        case 1.6..<1.8:
            makerApple["33"] = 0.0
            makerApple["48"] = (1.80 - stops) / 20.0
        default:
            makerApple["33"] = 0.0
            makerApple["48"] = (1.60101 - stops) / 0.101
        }

        imageProperties[kCGImagePropertyMakerAppleDictionary as String] = makerApple
        return sdrImage.settingProperties(imageProperties)
    }

    private static let maxAppleHeadroom: Float = 6.0
    private static let fallbackSourceHeadroom: Float = 3.0
    private static let imageQuality = 0.90
    private static let toneMappingRatio: CGFloat = 3.0
}

@available(macOS 15.0, *)
private final class HDRGainMapFilter: CIFilter {
    var hdrImage: CIImage?
    var sdrImage: CIImage?
    var maxHeadroom: Float?

    override var outputImage: CIImage? {
        guard let hdrImage, let sdrImage, let maxHeadroom else { return nil }
        return Self.kernel.apply(
            extent: hdrImage.extent,
            roiCallback: { _, rect in rect },
            arguments: [hdrImage, sdrImage, maxHeadroom]
        )
    }

    private static let kernel: CIColorKernel = {
        guard let data = Data(base64Encoded: gainMapKernelBase64) else {
            fatalError("Unable to decode GainMapKernel.ci.metallib")
        }
        guard let kernel = try? CIColorKernel(
            functionName: "GainMapFilter",
            fromMetalLibraryData: data
        ) else {
            fatalError("Unable to create GainMapFilter color kernel")
        }
        return kernel
    }()

    private static let gainMapKernelBase64 = [
        "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",
        "0EM5tAM8vIM8hAM7zPAUdmAHe2gHN2iHcmgHN4CHcJCHcGAHdigHdvgFdniHd4CHXwiHcRiHcpiH",
        "eZiBLO7wDu7gDvXADuwwA2LIoRzkoRzMoRzkoRzcYRzKIRzEgR3KYQbWkEM5yEM5mEM5yEM5uMM4",
        "lEM4iAM7lMMvvIM8/II71AM7sMMMx2mHcFiHcnCDdGgHeGCHdBiHdKCHGc5TD+4AD/JQDuSQDuNA",
        "D+EgDuxQDjMgKB3cwR7CQR7SIRzcgR7c4Bzk4R3qAR5mGFE4sEM6nIM7zFAkdmAHe2gHN2CHd3gH",
        "eJhRTPSQD/BQDjMeah7KYRzoIR3ewR1+AR7koRzMIR3wYQZUhYM4zMM7sEM90EM5/MI85EM7iMM7",
        "sMOMxQqHeZiHdxiHdAgHeigHcpiBXOMQDuzADuVQDvMwI8HSQR7k4RfY4R3eAR5mSBk7sIM9tIMb",
        "hMM4jEM5zMM8uME5yMM71AM8zEi0cQgHdmAHcQiHcViHGdvGDuxgD+3gBvAgD+UwD+UgD/ZQDm4Q",
        "DuMwDuUwD/PgBungDuRQDvgwI+LsYRzCgR3Y4RfsIR3mIR3EIR3YIR3oIR9mIJ07vEM9uAM5lIM5",
        "zFi8cHAHd3gHeggHekiHd3AHAAB5IAAA5QAAAHIeSCBDiAwZCXIySCAjgYyRkdFEoBAoZDwxMkKO",
        "kCGjmGH9Axa2QRu0KI0TGcwwFIaxbBwZxEGxCwAAAGFpci5tYXhfZGV2aWNlX2J1ZmZlcnNhaXIu",
        "bWF4X2NvbnN0YW50X2J1ZmZlcnNhaXIubWF4X3RocmVhZGdyb3VwX2J1ZmZlcnNhaXIubWF4X3Rl",
        "eHR1cmVzYWlyLm1heF9yZWFkX3dyaXRlX3RleHR1cmVzYWlyLm1heF9zYW1wbGVyc1NESyBWZXJz",
        "aW9ud2NoYXJfc2l6ZWZyYW1lLXBvaW50ZXJhaXIuY2lfYnVpbHRpbmFpci5hcmdfdHlwZV9uYW1l",
        "ZmxvYXQ0YWlyLmFyZ19uYW1laGRyc2RyZmxvYXRoZHJtYXhmbG9hdDJkZXN0LmNvZXJjZWFpci5j",
        "b21waWxlLmRlbm9ybXNfZGlzYWJsZWFpci5jb21waWxlLmZhc3RfbWF0aF9lbmFibGVhaXIuY29t",
        "cGlsZS5mcmFtZWJ1ZmZlcl9mZXRjaF9lbmFibGVBcHBsZSBtZXRhbCB2ZXJzaW9uIDMyMDIzLjg4",
        "MyAobWV0YWxmZS0zMjAyMy44ODMpTWV0YWwvVXNlcnMvbHV5YW8vRG9jdW1lbnRzL0dpdEh1Yi90",
        "b0dhaW5NYXBIRFIvdG9HYWluTWFwSERSL0N1c3RvbUZpbHRlci9HYWluTWFwS2VybmVsLmNpLm1l",
        "dGFsAAAAhk8AAAAAAAAwgoAIIwjIMIKAECMISDGCgBgjCMgxgpAwIwgIMoKAJCMIiDKCQAAjCMgy",
        "w6AF2wyDJmwzDNqwzTBoBDfDoBXdDINmeDMM3wEGMwxhgIjBDIOWfDMMXzcGMwzKwswQwMEMxhgo",
        "C9M4MxhhoCxM88xgfMoCNdEMRhkoi9RMMxByMAd0UAczDGQQB3YwQ0DNEFQzBNYMwTUDgYnBGIzB",
        "DEF2ZABwHMdxHMdxHMeJgRiIgRiIgRiggRuIARqIAacHekAHegAKdGBZlqUHMhKYoIzY2OzaXNre",
        "yOrYylzM2MLO5kZJysAMzgAN0kAN1oAN2iCXsDQ5F7syubm0N7dRAjdIIyxNzmUsbZTADnIKS5Nz",
        "GXtrg0tjK/t6g6NLe3ObG2W4AzzIg1TY2OzaXNLIytzoRgn0IKmwNDkXtjC3s7qws7IvuzK5ubQ3",
        "t1GCPUgqLE3OZe6tTm6s7Mssja3syy2srWyUgA8AAACpGAAAJQAAAAsKciiHd4AHelhwmEM9uMM4",
        "sEM50MOC5hzGoQ3oQR7CwR3mIR3oIR3ewR0WNONgDudQD+EgD+RAD+EgD+dQDvSwgIEHeSiHcGAH",
        "dniHcQgHeigHclhwnMM4tAE7pIM9lMMCaxzYIRzc4RzcIBzkYRzcIBzogR7CYRzQoRzIYRzCgR3Y",
        "YcEBD/QgD+FQD/SADgAAAADREAAABgAAAAfMPKSDO5wDO5QDPaCDPJRDOJDDAQAAAGEgAAB7AAAA",
        "EwRGLBAAAAAWAAAApCMAJVAEBGMEIAiC+DcaMEYA++xcfmMEuV668zdGgLP3mXsjAGMEIAiC+C+M",
        "EfBlb6beGAEIgmAKBmME5pyz7jdGgIJrjn9jBCMJ17wvUMxBVFVFAQAAAGMIE4QBI/5jCFWEQSP+",
        "OATgP4aATRg84o9DAP7DEQGk+McsQyAEYwhdhkEl/mMIn4aBJf44BOA/hiAGHAaY+OMQgD8GCvlj",
        "kIH/LIEwUAEIgR0AaAYb+KMQkP9wRDAGgn9MN5CBEAxHBB7hH7MMAxGg4In/LEExYnAMIQgW/lHo",
        "weBh4Ik/Bh74zxIUAxUAMgjEHMMXuMEcQyC4wRxDMLjBBuFANwAAAObTGADDAH8ETIjj04ZCAMPA",
        "W8NwDJHVEBIV9OYwSENkEMtASJMvOEQkEDeQIIU/HURT5ydgIIVPNIO1EAy11JYyCMxjMARDLbaJ",
        "EAy14HZTCMxT1/ZgHEPEAJedEAy17BdwIIVPLBJhNsWAVDVtOYXAPDVuJARDLbm5DMAwmMwwIJWt",
        "DAy1HEGCFD6xSES9H0BBNFOEWU8hUUHd24zxHIgfOKZTMNRS61eAIIVPNINNG0/BUEvNW1BSEQLS",
        "IJN9WwwBDMNtNEcETIjj04ZzRMCEOH5tJQQwDDoAAAAAAAAAcSAAAAMAAAAyDhAihADEBQAAAAAA",
        "AAAAZQwAACUAAAASA5QoAQAAAAMAAAAdAAAACQAAAEwAAAABAAAAWAAAAAAAAABYAAAAAgAAAIgA",
        "AAAAAAAAJgAAABwAAAANAAAAAAAAAA0AAAAAAAAAiAAAAAAAAAAAAAAAAgAAAAAAAAAAAAAADQAA",
        "AAAAAAANAAAA/////wAkAAANAAAAEAAAAA0AAAAQAAAA/////wgkAAAAAAAAXQwAABQAAAASA5Si",
        "AAAAAEdhaW5NYXBGaWx0ZXJhaXIuZmFzdF9wb3cuZjMyMzIwMjMuODgzYWlyNjRfdjI4LWFwcGxl",
        "LW1hY29zeDI2LjAuMAAAAAAAAAAAAAAAAAAAAAAAAE5BTUUBAABFTkRU"
    ].joined()
}

private enum HDRCaptureError: LocalizedError {
    case displayNotFound
    case gainMapFailed
    case outputCollision

    var errorDescription: String? {
        switch self {
        case .displayNotFound:
            return "HDR display not found"
        case .gainMapFailed:
            return "HDR gain map generation failed"
        case .outputCollision:
            return "Unable to create a unique HDR clipboard file"
        }
    }
}
