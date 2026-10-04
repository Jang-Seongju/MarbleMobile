import SwiftUI
import MarbleMobileCore

struct InformationDocument: Identifiable {
    let id = UUID()
    let title: String
    let lines: [InformationLine]
}

struct InformationDocumentView: View {
    let title: String
    let lines: [InformationLine]
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(lines.indices, id: \.self) { index in
                        let line = lines[index]
                        if line.isHeading {
                            Text(line.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .accessibilityAddTraits(.isHeader)
                        } else {
                            Text(line.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기", action: onClose)
                }
            }
        }
    }
}
