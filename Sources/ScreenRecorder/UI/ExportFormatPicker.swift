import SwiftUI

struct ExportFormatPicker: View {
    @Binding var selection: ExportFormat

    var body: some View {
        Picker("Format", selection: $selection) {
            ForEach(ExportFormat.allCases) { format in
                Text(format.rawValue).tag(format)
            }
        }
        .pickerStyle(.segmented)
    }
}
