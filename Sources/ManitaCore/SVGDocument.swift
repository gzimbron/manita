import Foundation

public struct SVGPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct SVGRect: Equatable, Sendable {
    public var x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    /// Edges included, so a point on the border is inside.
    public func contains(_ p: SVGPoint) -> Bool {
        p.x >= x && p.x <= x + width && p.y >= y && p.y <= y + height
    }
}

public enum SVGError: Error, Equatable {
    case notSVG
    case missingSize
}

/// The little the core needs to know about an SVG file: its user-unit box.
/// Drawing is left to the platform (`NSImage` on macOS).
public struct SVGDocument: Equatable, Sendable {
    public var viewBox: SVGRect

    /// Reads the root element: `viewBox`, or `width`/`height` when there is none.
    public static func parse(_ data: Data) throws -> SVGDocument {
        let reader = RootReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldResolveExternalEntities = false
        _ = parser.parse()
        guard let root = reader.attributes, reader.rootName == "svg" else { throw SVGError.notSVG }

        if let text = root["viewBox"] {
            let numbers = text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" || $0 == "\n" })
                .compactMap { Double($0) }
            if numbers.count == 4, numbers[2] > 0, numbers[3] > 0 {
                return SVGDocument(viewBox: SVGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]))
            }
            throw SVGError.missingSize
        }
        if let w = root["width"].flatMap(length), let h = root["height"].flatMap(length), w > 0, h > 0 {
            return SVGDocument(viewBox: SVGRect(x: 0, y: 0, width: w, height: h))
        }
        throw SVGError.missingSize
    }

    /// A plain number or one in px ("64", "48px").
    private static func length(_ text: String) -> Double? {
        Double(text.hasSuffix("px") ? String(text.dropLast(2)) : text)
    }

    private final class RootReader: NSObject, XMLParserDelegate {
        var rootName: String?
        var attributes: [String: String]?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
            if rootName == nil {
                rootName = name
                attributes = attributeDict
            }
            parser.abortParsing()
        }
    }
}
