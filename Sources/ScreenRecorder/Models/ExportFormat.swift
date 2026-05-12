import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4"
    case mpeg4 = "MPEG-4"
    case gif = "GIF"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .mp4: return "mp4"
        case .mpeg4: return "mpeg"
        case .gif: return "gif"
        }
    }

    var utType: UTType {
        switch self {
        case .mp4: return .mpeg4Movie
        case .mpeg4: return .mpeg4Movie
        case .gif: return .gif
        }
    }
}
