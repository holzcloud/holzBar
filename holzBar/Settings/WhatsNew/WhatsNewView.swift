//
//  WhatsNewView.swift
//  holzBar
//

import SwiftUI

/// The content of the What's New window: a header with the version, the pill tabs of the
/// versions, the notes of the selected one and a footer with the switch and Done.
///
/// The window is glass on the calm ground: the tab strip is its one glass layer, the rows
/// have none. It opens on the installed version, or on the newest one on a development build.
struct WhatsNewView: View {
    /// The width of the window's content.
    static let width: CGFloat = 560
    /// The least, ideal and greatest height of the window's content.
    static let heights: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (460, 640, 800)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @Bindable private var settings: GeneralSettings
    private let releases: [WhatsNewRelease]
    private let tabs: WhatsNewPolicy.Tabs
    private let onDone: () -> Void

    @State private var selection: String

    /// Creates the window content.
    ///
    /// - Parameters:
    ///   - settings: The settings that hold the "Show after an update" switch.
    ///   - releases: The release history, newest first.
    ///   - currentVersion: The version of the running app; `nil` on a development build.
    ///   - onDone: Called by the Done button and the Escape key.
    init(
        settings: GeneralSettings,
        releases: [WhatsNewRelease] = WhatsNewHistory.releases,
        currentVersion: String? = Bundle.main.versionString,
        onDone: @escaping () -> Void
    ) {
        let tabs = WhatsNewPolicy.tabs(knownVersions: releases.map(\.version), current: currentVersion)
        self.settings = settings
        self.releases = releases
        self.tabs = tabs
        self.onDone = onDone
        _selection = State(initialValue: tabs.installed ?? tabs.versions.first ?? "")
    }

    var body: some View {
        ZStack {
            HolzBarGround()
            VStack(alignment: .leading, spacing: 0) {
                header
                WhatsNewTabStrip(versions: tabs.versions, installed: tabs.installed, selection: $selection)
                    .padding(.horizontal, HolzBarTheme.Spacing.xl)
                    .padding(.bottom, HolzBarTheme.Spacing.md)
                notes
                footer
            }
        }
        .frame(width: Self.width)
        .frame(minHeight: Self.heights.min, idealHeight: Self.heights.ideal, maxHeight: Self.heights.max)
        .onExitCommand(perform: onDone)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
            HStack(spacing: HolzBarTheme.Spacing.xs) {
                Text("What's New")
                    .font(HolzBarTheme.Typography.headline)
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                PreviewBadge()
            }
            Text(verbatim: selection)
                .font(HolzBarTheme.Typography.display)
                .foregroundStyle(HolzBarTheme.Palette.text)
                .accessibilityLabel(String(localized: "Version \(selection)"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, HolzBarTheme.Spacing.xl)
        .padding(.top, HolzBarTheme.Spacing.xxl)
        .padding(.bottom, HolzBarTheme.Spacing.md)
    }

    // MARK: Notes

    private var notes: some View {
        ScrollView {
            if let release = releases.first(where: { $0.version == selection }) {
                WhatsNewReleaseBody(release: release)
                    .id(release.version)
                    .transition(.opacity)
                    .padding(.horizontal, HolzBarTheme.Spacing.xl)
                    .padding(.top, HolzBarTheme.Spacing.xs)
                    .padding(.bottom, HolzBarTheme.Spacing.xl)
            }
        }
        .animation(
            HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.smooth, reduceMotion: reduceMotion),
            value: selection
        )
        .mask { fadeMask }
    }

    /// A mask that fades the last points of the scrolling notes into the ground, a soft edge
    /// under which the rows disappear. With Reduce Transparency or Increase Contrast the notes
    /// end sharply instead.
    @ViewBuilder
    private var fadeMask: some View {
        let options = TransparencyOptions(
            reduceTransparency: reduceTransparency,
            increaseContrast: contrast == .increased
        )
        if options.prefersOpaque {
            Rectangle()
        } else {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: HolzBarTheme.Spacing.xl)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Toggle("Show after an update", isOn: $settings.showsWhatsNewAfterUpdate)
                .toggleStyle(.switch)
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(HolzBarTheme.Spacing.xl)
    }
}

#Preview("WhatsNewView") {
    WhatsNewView(
        settings: GeneralSettings(),
        releases: WhatsNewHistory.releases,
        currentVersion: "1.0.1"
    ) {}
}
