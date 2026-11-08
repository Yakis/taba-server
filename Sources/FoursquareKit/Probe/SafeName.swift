/// A file-name-safe version of an id, such as "osm:node/123" becoming "osm-node-123".
public enum SafeName {
    public static func make(_ text: String) -> String {
        String(text.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" })
    }
}
