//
//  WhatsNewView.swift
//  holzBar
//

import SwiftUI

/// The content of the What's New window: a header with the newest version shown, a main tab for
/// every major version, a sub tab for every minor version of it, the notes of that minor and a
/// footer with the switch and Done.
///
/// The notes of a minor are its releases one below the other, newest first, each as a section
/// that starts with its version; there is no tab per patch version. The window is glass on the
/// calm ground: the main strip is its one glass layer, the rows have none. It opens on the tabs
/// of the installed version, or of the newest one on a development build.
struct WhatsNewView: View {
    /// The width of the window's content.
    static let width: CGFloat = 560
    /// The least, ideal and greatest height of the window's content.
    static let heights: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (380, 520, 760)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @Bindable private var settings: GeneralSettings
    private let releases: [WhatsNewRelease]
    private let tabs: WhatsNewPolicy.Tabs
    private let majors: [WhatsNewMajorGroup]
    private let onDone: () -> Void

    @State private var majorSelection: String
    @State private var minorSelection: String

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
        let majors = WhatsNewGrouping.majors(of: tabs.versions)
        self.tabs = tabs
        self.majors = majors
        self.onDone = onDone
        let start = WhatsNewGrouping.location(of: tabs.installed ?? tabs.versions.first, in: majors)
            ?? majors.last.map { ($0.id, $0.minors.last?.id ?? "") }
        _majorSelection = State(initialValue: start?.major ?? "")
        _minorSelection = State(initialValue: start?.minor ?? "")
    }

    private var selectedMajor: WhatsNewMajorGroup? {
        majors.first { $0.id == majorSelection }
    }

    private var selectedMinor: WhatsNewMinorGroup? {
        selectedMajor?.minors.first { $0.id == minorSelection }
    }

    /// The tab ids of the installed version, to mark them with the wood dot.
    private var installedLocation: (major: String, minor: String)? {
        WhatsNewGrouping.location(of: tabs.installed, in: majors)
    }

    var body: some View {
        ZStack {
            HolzBarGround()
            VStack(alignment: .leading, spacing: 0) {
                header
                // A strip shows only when there is a choice to make.
                if majors.count > 1 {
                    WhatsNewTabStrip(
                        tabs: majors.map { .init(id: $0.id, title: $0.label) },
                        installed: installedLocation?.major,
                        selection: $majorSelection
                    )
                    .padding(.horizontal, HolzBarTheme.Spacing.xl)
                    .padding(.bottom, HolzBarTheme.Spacing.sm)
                }
                if (selectedMajor?.minors.count ?? 0) > 1 {
                    WhatsNewTabStrip(
                        tabs: (selectedMajor?.minors ?? []).map { .init(id: $0.id, title: $0.label) },
                        installed: installedLocation?.major == majorSelection ? installedLocation?.minor : nil,
                        isGlass: false,
                        selection: $minorSelection
                    )
                    .padding(.horizontal, HolzBarTheme.Spacing.xl)
                    Divider()
                        .padding(.horizontal, HolzBarTheme.Spacing.xl)
                }
                notes
                Divider()
                footer
            }
        }
        .frame(width: Self.width)
        .frame(minHeight: Self.heights.min, idealHeight: Self.heights.ideal, maxHeight: Self.heights.max)
        .onChange(of: majorSelection) { _, _ in
            // A new main tab opens on its newest minor.
            if selectedMinor == nil {
                minorSelection = selectedMajor?.minors.last?.id ?? ""
            }
        }
        .onExitCommand(perform: onDone)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: HolzBarTheme.Spacing.xs) {
            Text("What's New")
                .font(HolzBarTheme.Typography.headline)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .accessibilityAddTraits(.isHeader)
            PreviewBadge()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, HolzBarTheme.Spacing.xl)
        .padding(.top, HolzBarTheme.Spacing.xxl)
        .padding(.bottom, HolzBarTheme.Spacing.md)
    }

    // MARK: Notes

    private var notes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xl) {
                ForEach(selectedMinor?.versions ?? [], id: \.self) { version in
                    if let release = releases.first(where: { $0.version == version }) {
                        WhatsNewReleaseBody(
                            release: release,
                            showsVersion: true,
                            isInstalled: version == tabs.installed
                        )
                    }
                }
            }
            .id(minorSelection)
            .transition(.opacity)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HolzBarTheme.Spacing.xl)
            .padding(.top, HolzBarTheme.Spacing.md)
            .padding(.bottom, HolzBarTheme.Spacing.xl)
        }
        .animation(
            HolzBarTheme.Motion.resolved(HolzBarTheme.Motion.smooth, reduceMotion: reduceMotion),
            value: minorSelection
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
            HStack(spacing: HolzBarTheme.SettingsKit.accessoryGap) {
                Text("Show after an update")
                    .accessibilityHidden(true)
                SettingsSwitch(isOn: $settings.showsWhatsNewAfterUpdate, label: Text("Show after an update"))
            }
            Spacer()
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, HolzBarTheme.Spacing.xl)
        .padding(.vertical, HolzBarTheme.Spacing.md)
    }
}

#Preview("WhatsNewView") {
    WhatsNewView(
        settings: GeneralSettings(),
        releases: WhatsNewHistory.releases,
        currentVersion: "1.0.1"
    ) {}
}
