import Foundation

enum AudioPreset: String, CaseIterable, Identifiable {
    case calm
    case adventurous
    case electronic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calm: return "Calm"
        case .adventurous: return "Adventurous"
        case .electronic: return "Electronic"
        }
    }
}

enum AudioTrackChoice: Equatable {
    case none
    case preset(AudioPreset)
    case custom(URL)

    var displayName: String {
        switch self {
        case .none: return "No Audio"
        case .preset(let p): return p.displayName
        case .custom(let url): return url.lastPathComponent
        }
    }

    var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    var preset: AudioPreset? {
        if case .preset(let p) = self { return p }
        return nil
    }
}
