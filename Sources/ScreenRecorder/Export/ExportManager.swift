import AppKit
import UniformTypeIdentifiers

@MainActor
class ExportManager {

    func export(videoAt sourceURL: URL, as format: ExportFormat) async throws -> URL? {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Recording"
        savePanel.nameFieldStringValue = "recording.\(format.fileExtension)"
        savePanel.allowedContentTypes = [format.utType]
        savePanel.canCreateDirectories = true

        let response = savePanel.runModal()
        guard response == .OK, let destURL = savePanel.url else {
            return nil
        }

        switch format {
        case .mp4:
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return destURL

        case .mpeg4:
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return destURL

        case .gif:
            try await GIFExporter.export(videoURL: sourceURL, outputURL: destURL)
            return destURL
        }
    }
}
