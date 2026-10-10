//
//  ProfileHooksSection.swift
//  holzBar
//

import SwiftUI

/// The scripts that run before or after a layout profile is applied. A hook is for one profile
/// or for every profile, and names a script the user allowed. This is the only place hooks are
/// seen or set.
struct ProfileHooksSection: View {
    @Environment(AppState.self) private var appState
    let store: ScriptStore

    private var profileNames: [String] {
        appState.profiles.profiles.map(\.name)
    }

    /// The names of the scripts the user allowed and that may run now.
    private var allowedScriptNames: [String] {
        store.scripts.compactMap { entry in
            if case .allowed = entry.decision {
                return entry.name
            }
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.sm) {
            HStack(spacing: HolzBarTheme.Spacing.sm) {
                Text("Profile Hooks")
                    .font(HolzBarTheme.Typography.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(HolzBarTheme.Palette.textTertiary)
                PreviewBadge()
            }
            VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xxs) {
                Text("Run a script you allowed before or after a layout profile is applied.")
                Text("holzBar waits for scripts that run before a profile, up to their time limit.")
                Text("A profile applied by a URL, a Shortcut or a Focus runs no hooks.")
            }
            .font(HolzBarTheme.Typography.caption)
            .foregroundStyle(HolzBarTheme.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            ForEach(store.profileHooks) { hook in
                row(for: hook)
            }
            HStack {
                Button("Add Hook", systemImage: "plus") {
                    addHook()
                }
                .disabled(allowedScriptNames.isEmpty || store.profileHooks.count >= ProfileHooks.maximumCount)
                if allowedScriptNames.isEmpty {
                    Text("Allow a script above first.")
                        .font(HolzBarTheme.Typography.caption)
                        .foregroundStyle(HolzBarTheme.Palette.textTertiary)
                }
                Spacer()
            }
        }
    }

    private func addHook() {
        guard let scriptName = allowedScriptNames.first else {
            return
        }
        store.addProfileHook(
            ProfileHook(profileName: profileNames.first, timing: .afterApplying, scriptName: scriptName)
        )
    }

    // MARK: Rows

    private func row(for hook: ProfileHook) -> some View {
        VStack(alignment: .leading, spacing: HolzBarTheme.Spacing.xs) {
            HStack(spacing: HolzBarTheme.Spacing.sm) {
                Picker("Profile", selection: profileBinding(for: hook)) {
                    Text("Every Profile").tag(String?.none)
                    ForEach(profileOptions(for: hook), id: \.self) { name in
                        Text(verbatim: URLPrompt.displayName(name)).tag(String?.some(name))
                    }
                }
                Spacer()
                Button {
                    store.removeProfileHook(id: hook.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(HolzBarTheme.Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove Hook"))
            }
            Picker("When", selection: timingBinding(for: hook)) {
                Text("Before Applying").tag(ProfileHookTiming.beforeApplying)
                Text("After Applying").tag(ProfileHookTiming.afterApplying)
            }
            Picker("Script", selection: scriptBinding(for: hook)) {
                ForEach(scriptOptions(for: hook), id: \.self) { name in
                    Text(verbatim: URLPrompt.displayName(name)).tag(name)
                }
            }
        }
        .padding(.horizontal, HolzBarTheme.Spacing.sm)
        .padding(.vertical, HolzBarTheme.Spacing.xs + 2)
        .background(
            HolzBarTheme.Palette.text.opacity(0.05),
            in: HolzBarTheme.shape(HolzBarTheme.Radius.control)
        )
    }

    /// The profiles to choose from. A profile the hook names that no longer exists stays in the
    /// list, so the row keeps saying what it is for.
    private func profileOptions(for hook: ProfileHook) -> [String] {
        var names = profileNames
        if let name = hook.profileName, !names.contains(name) {
            names.append(name)
        }
        return names
    }

    /// The scripts to choose from. A script the hook names that is not allowed now stays in the
    /// list; the hook then runs nothing until it is allowed again.
    private func scriptOptions(for hook: ProfileHook) -> [String] {
        var names = allowedScriptNames
        if !names.contains(hook.scriptName) {
            names.append(hook.scriptName)
        }
        return names
    }

    // MARK: Bindings

    private func profileBinding(for hook: ProfileHook) -> Binding<String?> {
        Binding(
            get: { hook.profileName },
            set: { name in
                change(hook) { $0.profileName = name }
            }
        )
    }

    private func timingBinding(for hook: ProfileHook) -> Binding<ProfileHookTiming> {
        Binding(
            get: { hook.timing },
            set: { timing in
                change(hook) { $0.timing = timing }
            }
        )
    }

    private func scriptBinding(for hook: ProfileHook) -> Binding<String> {
        Binding(
            get: { hook.scriptName },
            set: { name in
                change(hook) { $0.scriptName = name }
            }
        )
    }

    /// Changes the stored hook with the same identity; the store checks the result again.
    private func change(_ hook: ProfileHook, _ update: (inout ProfileHook) -> Void) {
        guard var current = store.profileHooks.first(where: { $0.id == hook.id }) else {
            return
        }
        update(&current)
        store.updateProfileHook(current)
    }
}
