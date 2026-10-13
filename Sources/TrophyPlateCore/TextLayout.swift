import Foundation
import CoreText
import CoreGraphics

public struct LayoutLine {
    public let text: String
    public let bounds: CGRect
    public let path: CGPath
}
public struct PlateLayout {
    public let lines: [LayoutLine]
    public let bounds: CGRect
}
public enum TextLayout {
    public static func make(_ design: PlateDesign) throws -> PlateLayout {
        try design.validate()
        var entries = [(design.presenter,design.nameSize),(design.title1,design.titleSize)]
        if !design.title2.trimmingCharacters(in: .whitespaces).isEmpty { entries.append((design.title2,design.titleSize)) }
        entries.append((design.date,design.dateSize))
        let mmPerPoint = 25.4 / 72.0
        var shapes: [(String,CGPath,CGRect)] = []
        for (text,size) in entries {
            let font = CTFontCreateWithName(design.fontName as CFString, size * mmPerPoint, nil)
            let attr = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String):font])
            let line = CTLineCreateWithAttributedString(attr)
            let combined = CGMutablePath()
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating:0,count:count)
                var positions = [CGPoint](repeating:.zero,count:count)
                var indices = [CFIndex](repeating:0,count:count)
                CTRunGetGlyphs(run, CFRange(location:0,length:0), &glyphs)
                CTRunGetPositions(run, CFRange(location:0,length:0), &positions)
                CTRunGetStringIndices(run, CFRange(location:0,length:0), &indices)
                let attrs = CTRunGetAttributes(run) as NSDictionary
                let runFont = attrs[kCTFontAttributeName] as! CTFont
                for i in 0..<count {
                    let utf16 = text as NSString
                    let scalar = indices[i] >= 0 && indices[i] < utf16.length ? UnicodeScalar(utf16.character(at:indices[i])):nil
                    let whitespace = scalar.map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
                    if glyphs[i] != 0, let path = CTFontCreatePathForGlyph(runFont,glyphs[i],nil), !path.isEmpty {
                        combined.addPath(path,transform:CGAffineTransform(translationX:positions[i].x,y:positions[i].y))
                    } else if !whitespace {
                        throw PlateError("A character in ‘\(text)’ has no engravable outline. Remove unsupported symbols or choose another font.")
                    }
                }
            }
            let bounds = combined.boundingBoxOfPath
            guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { throw PlateError("Text contains no engravable outlines. Choose a different font or text.") }
            shapes.append((text,combined,bounds))
        }
        let height = shapes.reduce(0) { $0 + $1.2.height } + Double(shapes.count-1)*design.lineSpacing
        guard height <= 40-2*design.margin, shapes.allSatisfy({ $0.2.width <= 80-2*design.margin }) else { throw PlateError("Text exceeds the plate margins. Reduce font size or shorten the text.") }
        var top = (40+height)/2
        var lines: [LayoutLine] = []
        for (text,path,bounds) in shapes {
            let target = CGRect(x:(80-bounds.width)/2,y:top-bounds.height,width:bounds.width,height:bounds.height)
            var transform = CGAffineTransform(translationX:target.minX-bounds.minX,y:target.minY-bounds.minY)
            guard let placed = path.copy(using:&transform) else { throw PlateError("Unable to position text.") }
            lines.append(LayoutLine(text:text,bounds:target,path:placed))
            top = target.minY-design.lineSpacing
        }
        return PlateLayout(lines:lines,bounds:lines.reduce(CGRect.null) { $0.union($1.bounds) })
    }
}
