//
//  OnboardingView.swift
//  holzBar
//

import SwiftUI

/// The three steps of the onboarding (D-36): what holzBar does, how to show hidden items, and
/// how to arrange the menu bar. Skip closes it on every step, Escape too, and Return goes on
/// (D-37). Every sentence says what is true on this Mac.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var step = OnboardingStep.whatHolzBarDoes
    /// The proposals of step 3, read once when the step shows.
    @State private var proposalCount: Int?

    let onClose: () -> Void

    var body: some View {
        VStack(spacing: HolzBarTheme.Spacing.lg) {
            picture
                .frame(height: HolzBarTheme.Onboarding.pictureHeight)
                .accessibilityHidden(true)
            Text(title)
                .font(HolzBarTheme.Typography.title)
                .foregroundStyle(HolzBarTheme.Palette.text)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: HolzBarTheme.Spacing.sm) {
                ForEach(Array(sentences.enumerated()), id: \.offset) { _, sentence in
                    sentence
                }
            }
            .font(HolzBarTheme.Typography.body)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            buttons
            dots
        }
        .padding(HolzBarTheme.Spacing.xl)
        .frame(width: HolzBarTheme.Onboarding.width)
        .background {
            HolzBarGround(showsGlows: false)
                .ignoresSafeArea()
        }
        .onExitCommand(perform: onClose)
        .onChange(of: step) { _, newStep in
            if newStep == .arrange, proposalCount == nil {
                proposalCount = TidyUpEntry.proposals(from: appState).count
            }
        }
    }

    // MARK: Content

    private var title: LocalizedStringKey {
        switch step {
        case .whatHolzBarDoes: "What holzBar does"
        case .showHiddenItems: "How to show hidden items"
        case .arrange: "Arrange your menu bar"
        }
    }

    private var sentences: [Text] {
        switch step {
        case .whatHolzBarDoes:
            return [Text("holzBar splits your menu bar into Visible and Hidden. What you rarely need goes behind the holzBar icon and stays one click away.")]
        case .showHiddenItems:
            var result = [Text("Click the holzBar icon to show the hidden items, and click it again to hide them.")]
            let general = appState.settings.general
            if OnboardingPolicy.mentionsClickAndScroll(showOnClick: general.showOnClick, showOnScroll: general.showOnScroll) {
                result.append(Text("You can also click an empty spot of the menu bar or scroll in it."))
            }
            switch OnboardingPolicy.hidingWay(isMacOS27: isMacOS27) {
            case .commandDrag:
                result.append(Text("To hide an item, ⌘ Command-drag it to the left of the holzBar icon, or arrange it in Layout."))
            case .perApp:
                result.append(Text("On this Mac, holzBar hides whole apps: the items of one app belong together. Arrange them in Layout."))
            }
            return result
        case .arrange:
            return [Text("holzBar suggests what can be hidden. You decide, nothing leaves your Mac, and you can undo it.")]
        }
    }

    private var isMacOS27: Bool {
        if #available(macOS 27.0, *) {
            return true
        }
        return false
    }

    private var hasProposals: Bool {
        (proposalCount ?? 0) > 0
    }

    // MARK: Picture

    @ViewBuilder
    private var picture: some View {
        switch step {
        case .whatHolzBarDoes, .showHiddenItems:
            strip(dimsHidden: step == .whatHolzBarDoes)
        case .arrange:
            if let proposalCount, proposalCount > 0 {
                VStack(spacing: HolzBarTheme.Spacing.xs) {
                    Image(systemName: "wand.and.stars")
                        .font(HolzBarTheme.Typography.title)
                        .foregroundStyle(HolzBarTheme.Palette.accent)
                        .accessibilityHidden(true)
                    Text("\(proposalCount) items work in the background")
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                }
            } else {
                Image(systemName: "wand.and.stars")
                    .font(HolzBarTheme.Typography.titleLarge)
                    .foregroundStyle(HolzBarTheme.Palette.accent)
                    .accessibilityHidden(true)
            }
        }
    }

    /// A small menu bar: two items, the holzBar mark, and two hidden items, which step 1 dims.
    private func strip(dimsHidden: Bool) -> some View {
        HStack(spacing: HolzBarTheme.Spacing.md) {
            Image(systemName: "moon.fill")
                .accessibilityHidden(true)
            Image(systemName: "wifi")
                .accessibilityHidden(true)
            Image(.logoStroke)
                .resizable()
                .scaledToFit()
                .frame(height: HolzBarTheme.Onboarding.pictureHeight / 2)
                .foregroundStyle(HolzBarTheme.Palette.accent)
                .accessibilityHidden(true)
            Group {
                Image(systemName: "terminal")
                    .accessibilityHidden(true)
                Image(systemName: "icloud")
                    .accessibilityHidden(true)
            }
            .opacity(dimsHidden ? HolzBarTheme.SettingsKit.dependentOpacity : 1)
        }
        .font(HolzBarTheme.Typography.body)
        .foregroundStyle(HolzBarTheme.Palette.text)
        .padding(.horizontal, HolzBarTheme.Spacing.lg)
        .frame(maxHeight: .infinity)
        .background(HolzBarTheme.Palette.accent.opacity(fillOpacity), in: Capsule())
    }

    private var fillOpacity: Double {
        colorScheme == .dark
            ? HolzBarTheme.SettingsKit.accentFillDark
            : HolzBarTheme.SettingsKit.accentFillLight
    }

    // MARK: Buttons

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: HolzBarTheme.Spacing.sm) {
            Button("Skip", action: onClose)
            Spacer(minLength: 0)
            if step == .arrange {
                if hasProposals {
                    Button("Arrange Myself", action: arrangeMyself)
                    Button("View Suggestion", action: viewSuggestion)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Arrange Myself", action: arrangeMyself)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Button("Continue") {
                    if let next = step.next {
                        step = next
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: HolzBarTheme.Spacing.xs) {
            ForEach(OnboardingStep.allCases, id: \.self) { dotStep in
                Circle()
                    .fill(dotStep == step ? HolzBarTheme.Palette.accent : HolzBarTheme.Palette.textTertiary)
                    .frame(width: HolzBarTheme.Onboarding.dotSize, height: HolzBarTheme.Onboarding.dotSize)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(step.number) of \(OnboardingStep.count)"))
    }

    // MARK: Actions

    /// Opens Layout to arrange the bar by hand.
    private func arrangeMyself() {
        openLayout(showingTidyUp: false)
    }

    /// Opens Layout with the Tidy Up sheet, as the old alert did; the suggestion is answered.
    private func viewSuggestion() {
        Defaults.set(true, forKey: .cleanUpOffered)
        openLayout(showingTidyUp: true)
    }

    private func openLayout(showingTidyUp: Bool) {
        let navigationState = appState.navigationState
        navigationState.settingsNavigationIdentifier = .menuBarLayout
        if showingTidyUp {
            navigationState.isTidyUpPresented = true
        }
        onClose()
        appState.activate(for: .settings)
        appState.openWindow(.settings)
    }
}
