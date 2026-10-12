//
//  AboutSettingsPane.swift
//  holzBar
//

import SwiftUI

struct AboutSettingsPane: View {
    @Environment(AppState.self) var appState
    @Environment(\.openURL) private var openURL
    @State private var isShowingAcknowledgements = false
    @State private var isShowingDiagnostics = false

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                contentForm(cornerStyle: .continuous)
            } else {
                contentForm(cornerStyle: .circular)
            }
        }
        .sheet(isPresented: $isShowingAcknowledgements) {
            AcknowledgementsView()
        }
        .sheet(isPresented: $isShowingDiagnostics) {
            DiagnosticsSheet()
        }
    }

    @ViewBuilder
    private func contentForm(cornerStyle: RoundedCornerStyle) -> some View {
        HolzBarForm(spacing: 0) {
            mainContent(containerShape: RoundedRectangle(cornerRadius: 20, style: cornerStyle))
            Spacer(minLength: 10)
            bottomBar(containerShape: Capsule(style: cornerStyle))
        }
    }

    @ViewBuilder
    private func mainContent(containerShape: some InsettableShape) -> some View {
        HolzBarSection(spacing: 0, options: .plain) {
            appIconAndCopyrightSection
                .layoutPriority(1)

            Spacer(minLength: 0)
                .frame(maxHeight: 20)

            updatesSection
                .layoutPriority(1)
        }
        .padding(.top, 5)
        .padding([.horizontal, .bottom], 30)
        .frame(maxHeight: 500)
        .background(.quinary, in: containerShape)
        .containerShape(containerShape)
    }

    @ViewBuilder
    private var appIconAndCopyrightSection: some View {
        HolzBarSection(options: .plain) {
            HStack(spacing: 10) {
                if let nsImage = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 230)
                }

                VStack(alignment: .leading) {
                    Text("holzBar")
                        .font(.system(size: 64))
                        .foregroundStyle(.primary)

                    Text("Version \(Constants.versionString)")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)

                    Text(Constants.copyrightString)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary.opacity(0.67))

                    basedOnIce
                        .padding(.top, 6)
                }
                .fontWeight(.medium)
            }
        }
    }

    /// The credit to the original Ice, which holzBar is a fork of.
    @ViewBuilder
    private var basedOnIce: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.pink)
            Text("Based on")
            Link("Ice", destination: Constants.originalIceURL)
            Text("by Jordan Baird")
        }
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var updatesSection: some View {
        HolzBarSection(options: .hasDividers) {
            HStack {
                Text("Updates are installed with Homebrew:")
                Spacer()
                Text("brew update && brew upgrade --cask holzbar")
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            HStack {
                Text("Release notes for every version are on GitHub.")
                Spacer()
                Button("Releases") {
                    openURL(Constants.releasesURL)
                }
            }
        }
        .frame(maxWidth: 600)
    }

    @ViewBuilder
    private func bottomBar(containerShape: some InsettableShape) -> some View {
        HStack {
            Button("Quit holzBar") {
                NSApp.terminate(nil)
            }
            Spacer()
            Button("Acknowledgements") {
                isShowingAcknowledgements = true
            }
            Button("Website") {
                openURL(Constants.websiteURL)
            }
            Button("Contribute") {
                openURL(Constants.repositoryURL)
            }
            Button("Copy Diagnostics…", systemImage: "doc.on.clipboard") {
                isShowingDiagnostics = true
            }
            Button("Report a Bug", systemImage: "ladybug") {
                openURL(Constants.issuesURL)
            }
        }
        .padding(8)
        .buttonStyle(BottomBarButtonStyle())
        .background(.quinary, in: containerShape)
        .containerShape(containerShape)
        .frame(height: 40)
    }
}

private struct BottomBarButtonStyle: ButtonStyle {
    @State private var isHovering = false

    private var borderShape: some InsettableShape {
        ContainerRelativeShape()
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                borderShape
                    .fill(configuration.isPressed ? .tertiary : .quaternary)
                    .opacity(isHovering ? 1 : 0)
            }
            .contentShape([.focusEffect, .interaction], borderShape)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}
