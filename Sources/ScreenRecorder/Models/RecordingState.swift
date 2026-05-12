import Foundation

enum RecordingState: Equatable {
    case idle
    case selectingRegion
    case countingDown(Int)
    case recording
    case processing
    case done(URL)
    case editing(URL)
    case error(String)

    static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.selectingRegion, .selectingRegion),
             (.recording, .recording),
             (.processing, .processing):
            return true
        case (.countingDown(let a), .countingDown(let b)):
            return a == b
        case (.done(let a), .done(let b)):
            return a == b
        case (.editing(let a), .editing(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }

    var isEditing: Bool {
        if case .editing = self { return true }
        return false
    }
}
