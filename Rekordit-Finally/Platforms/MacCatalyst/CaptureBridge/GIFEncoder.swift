import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Frame {
    let url: URL
    let time: Double
}

func encodeGIF(frames: [Frame], directory: URL, duration: Double) throws -> URL {
    guard !frames.isEmpty else { throw NSError(domain:"Rekordit",code:2,userInfo:[NSLocalizedDescriptionKey:"No frames were captured. Check Screen Recording permission and try again."]) }
    let url = directory.appendingPathComponent("Recording.gif")
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (index, frame) in frames.enumerated() {
        try autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(frame.url as CFURL,nil), let image = CGImageSourceCreateImageAtIndex(source,0,nil) else { throw CocoaError(.fileReadCorruptFile) }
            let end = index+1 < frames.count ? frames[index+1].time : duration
            let delay = max(0.02, end - (index == 0 ? 0 : frame.time))
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime:delay,kCGImagePropertyGIFUnclampedDelayTime:delay]] as CFDictionary)
        }
    }
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    return url
}

// Unique names preserve previous recordings and copy leaves the source intact on failure.
func saveRecording(_ gif: URL, in directory: URL) throws -> URL {
    let destination = directory.appendingPathComponent("Rekordit-\(UUID().uuidString).gif")
    try FileManager.default.copyItem(at: gif, to: destination)
    return destination
}
