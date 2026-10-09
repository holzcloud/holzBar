//
//  TidyUpSheet.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The clean-up assistant: proposes to hide the items that work in the background and are
/// rarely clicked, from static facts only (the system's own extras, the application's
/// category, a short list of known helpers). Nothing is observed or recorded. The user
/// decides item by item; before anything moves the arrangement is kept as a snapshot.
struct TidyUpSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [TidyUpEntry] = []
    @State private var kept = Set<String>()
    @State private var hasLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.md) {
            Text("Tidy Up")
                .font(HolzBarTheme.Typography.title)
            Text("holzBar looked at the apps in your menu bar on this Mac. Nothing leaves your Mac and nothing is recorded. It proposes to hide what works in the background; the clock, the battery and apps with messages stay. Uncheck what should stay visible.")
                .font(HolzBarTheme.Typography.callout)
                .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if hasLoaded && entries.isEmpty {
                Text("Nothing to propose: your menu bar is tidy already.")
                    .foregroundStyle(HolzBarTheme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List(entries) { entry in
                    Toggle(isOn: isHidden(entry.id)) {
                        HStack(spacing: HolzBarTheme.Spacing.sm) {
                            if let icon = entry.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                    .accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: entry.name)
                                Text(entry.reasonText)
                                    .font(HolzBarTheme.Typography.caption)
                                    .foregroundStyle(HolzBarTheme.Palette.textTertiary)
                            }
                        }
                    }
                }
                .frame(height: 240)
            }
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Spacer()
                Button("Hide Selected") {
                    apply()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(entries.isEmpty || kept.count == entries.count)
            }
        }
        .padding(HolzBarTheme.Spacing.lg)
        .frame(width: 520)
        .onAppear {
            entries = TidyUpEntry.proposals(from: appState)
            hasLoaded = true
        }
    }

    /// Whether the item is checked to be hidden.
    private func isHidden(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !kept.contains(id) },
            set: { isOn in
                if isOn {
                    kept.remove(id)
                } else {
                    kept.insert(id)
                }
            }
        )
    }

    private func apply() {
        let chosen = entries.filter { !kept.contains($0.id) }
        guard !chosen.isEmpty else {
            return
        }
        appState.snapshots.willTidyUp()
        let layout = appState.profiles.currentLayout()
        var itemSections = layout.itemSections
        var applicationSections = layout.applicationSections
        for entry in chosen {
            itemSections[entry.proposal.item.key] = 1
            if SharedProfile.isValidBundleIdentifier(entry.proposal.item.namespace) {
                applicationSections[entry.proposal.item.namespace] = 1
            }
        }
        appState.profiles.applyLayout(of: LayoutProfile(
            name: "",
            itemSections: itemSections,
            applicationSections: applicationSections,
            knownApplications: layout.knownApplications
        ))
    }
}

/// One proposal with what the sheet shows of it.
struct TidyUpEntry: Identifiable {
    let proposal: CleanUpProposal
    let name: String
    let icon: NSImage?

    var id: String { proposal.item.key }

    var reasonText: LocalizedStringKey {
        switch proposal.reason {
        case .systemExtra: "A system extra you rarely need on the bar"
        case .backgroundTool: "A utility that works in the background"
        case .knownHelper: "A helper that works in the background"
        }
    }

    /// The proposals for the items in the menu bar now.
    @MainActor
    static func proposals(from appState: AppState) -> [TidyUpEntry] {
        let itemManager = appState.itemManager
        var byKey = [String: MenuBarItem]()
        var classifiable = [ClassifiableItem]()
        for section in MenuBarSection.Name.allCases {
            for item in itemManager.itemCache[section] where !item.isControlItem {
                let key = itemManager.identityKey(for: item)
                byKey[key] = item
                classifiable.append(ClassifiableItem(
                    key: key,
                    namespace: item.tag.namespace.description,
                    title: item.tag.title,
                    applicationCategory: applicationCategory(of: item),
                    section: section.profileIndex
                ))
            }
        }
        return ItemClassifier.proposals(for: classifiable).compactMap { proposal in
            guard let item = byKey[proposal.item.key] else {
                return nil
            }
            return TidyUpEntry(proposal: proposal, name: item.displayName, icon: appState.itemIconStore.appIcon(for: item))
        }
    }

    /// The `LSApplicationCategoryType` of the item's application, read from its bundle.
    @MainActor
    private static func applicationCategory(of item: MenuBarItem) -> String? {
        guard let url = item.sourceApplication?.bundleURL, let bundle = Bundle(url: url) else {
            return nil
        }
        return bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
    }
}
