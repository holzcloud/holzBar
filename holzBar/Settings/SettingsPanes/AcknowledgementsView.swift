//
//  AcknowledgementsView.swift
//  holzBar
//

import SwiftUI

/// holzBar's license, the code it is based on and the open-source packages it links,
/// shown as a sheet from the About pane.
///
/// Nothing is fetched: license texts are bundled resources, loaded only when their
/// group is expanded, and links open the browser only when clicked.
struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Acknowledgements")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    holzBarGroup
                    adaptedCodeGroup
                    packagesGroup
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560)
        .frame(minHeight: 480, idealHeight: 560, maxHeight: 640)
    }

    @ViewBuilder
    private var holzBarGroup: some View {
        AcknowledgementsGroup(title: "holzBar") {
            Text("holzBar is free software, licensed under the \(Acknowledgements.gplLicense).")
                .fixedSize(horizontal: false, vertical: true)
            Link("License", destination: Constants.repositoryURL.appending(path: "blob/main/LICENSE"))
        }
    }

    @ViewBuilder
    private var adaptedCodeGroup: some View {
        AcknowledgementsGroup(title: "Based on") {
            ForEach(Acknowledgements.adaptedCode) { acknowledgement in
                AcknowledgementRow(acknowledgement: acknowledgement)
            }
        }
    }

    @ViewBuilder
    private var packagesGroup: some View {
        AcknowledgementsGroup(title: "Open-source packages") {
            ForEach(Acknowledgements.packages) { acknowledgement in
                AcknowledgementRow(acknowledgement: acknowledgement)
            }
        }
    }
}

/// A titled group of the acknowledgements sheet.
private struct AcknowledgementsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
    }
}

/// One project of the acknowledgements sheet, with its license text when it has one.
private struct AcknowledgementRow: View {
    let acknowledgement: Acknowledgement

    @State private var isLicenseExpanded = false
    @State private var licenseText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(acknowledgement.name)
                    .fontWeight(.semibold)
                if let version = acknowledgement.version {
                    Text(version)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let url = URL(string: acknowledgement.repository) {
                    Link("Repository", destination: url)
                }
            }

            Text(acknowledgement.use)
                .fixedSize(horizontal: false, vertical: true)

            Text(acknowledgement.license)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let licenseFile = acknowledgement.licenseFile {
                DisclosureGroup("License", isExpanded: $isLicenseExpanded) {
                    Text(licenseText ?? "")
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .onChange(of: isLicenseExpanded) { _, isExpanded in
                    if isExpanded, licenseText == nil {
                        licenseText = Self.loadLicenseText(named: licenseFile)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// The bundled license text of the given base name, or a note that it is missing.
    private static func loadLicenseText(named name: String) -> String {
        let url = Bundle.main.url(forResource: name, withExtension: "txt")
            ?? Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Acknowledgements")
        guard
            let url,
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "The license text is missing from this copy of holzBar."
        }
        return text
    }
}
