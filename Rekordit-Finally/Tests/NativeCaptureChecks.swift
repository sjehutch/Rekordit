// Run from the repository root:
// xcrun swiftc Rekordit-Finally/Platforms/MacCatalyst/CaptureBridge/{SelectionGeometry,GIFEncoder}.swift Rekordit-Finally/Tests/NativeCaptureChecks.swift -o /tmp/rekordit-checks && /tmp/rekordit-checks
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main struct NativeCaptureChecks {
    static func main() throws {
        let bounds = CGRect(x:0,y:0,width:1000,height:800)
        assert(draggedRect(from:CGPoint(x:500,y:400),to:CGPoint(x:100,y:100),within:bounds) == CGRect(x:100,y:100,width:400,height:300))
        let rect = CGRect(x:100,y:100,width:400,height:300)
        assert(movedRect(rect,dx:1000,dy:-1000,within:bounds) == CGRect(x:600,y:0,width:400,height:300))
        assert(resizedRect(rect,handle:4,to:CGPoint(x:750,y:600),within:bounds) == CGRect(x:100,y:100,width:650,height:500))
        assert(resizedRect(rect,handle:0,to:CGPoint(x:999,y:999),within:bounds) == CGRect(x:476,y:376,width:24,height:24))
        assert(draggedRect(from:CGPoint(x:10,y:10),to:CGPoint(x:2000,y:2000),within:bounds).maxX == 1000)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        var frames: [Frame] = []
        for index in 0..<2 {
            let context = CGContext(data:nil,width:120,height:80,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red:index == 0 ? 1 : 0,green:0,blue:index == 1 ? 1 : 0,alpha:1))
            context.fill(CGRect(x:0,y:0,width:120,height:80))
            let url = directory.appendingPathComponent("\(index).png")
            let destination = CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
            CGImageDestinationAddImage(destination,context.makeImage()!,nil)
            assert(CGImageDestinationFinalize(destination))
            frames.append(Frame(url:url,time:index == 0 ? 0.1 : 0.5))
        }
        let gif = try encodeGIF(frames:frames,directory:directory,duration:1)
        let source = CGImageSourceCreateWithURL(gif as CFURL,nil)!
        assert(CGImageSourceGetCount(source) == 2)
        let image = CGImageSourceCreateImageAtIndex(source,0,nil)!
        assert(image.width == 120 && image.height == 80)
        for index in 0..<2 {
            let properties = CGImageSourceCopyPropertiesAtIndex(source,index,nil)! as NSDictionary
            let gifProperties = properties[kCGImagePropertyGIFDictionary] as! NSDictionary
            assert(abs((gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as! NSNumber).doubleValue - 0.5) < 0.001)
        }
        let saved = try saveRecording(gif, in: directory)
        let second = try saveRecording(gif, in: directory)
        assert(saved != second)
        let originalData = try Data(contentsOf: gif)
        let savedData = try Data(contentsOf: saved)
        assert(originalData == savedData)
        do {
            _ = try saveRecording(gif, in: directory.appendingPathComponent("missing"))
            assertionFailure("Saving to a missing folder must fail")
        } catch { assert(FileManager.default.fileExists(atPath: gif.path)) }
        do { _ = try encodeGIF(frames:[],directory:directory,duration:1); assertionFailure("An empty recording must fail") }
        catch { }
        print("Selection geometry, native GIF dimensions, frame timing, unique saves, source preservation, and empty-recording checks passed.")
    }
}
