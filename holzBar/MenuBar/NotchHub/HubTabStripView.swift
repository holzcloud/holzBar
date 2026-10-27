//
//  HubTabStripView.swift
//  holzBar
//

import SwiftUI

/// The icon strip in the Notch hub's left wing: the Overview, then one tab per module that
/// offers one, and a More menu for the tabs that do not fit.
///
/// The selected tab is tinted by its module. Each tab is 24 points high to the eye, and its
/// hit area is the whole height of the top row.
struct HubTabStripView: View {
    let model: NotchHubModel
    /// The width of the wing, which decides how many tabs fit.
    let wingWidth: CGFloat
    /// The height of the top row.
    let rowHeight: CGFloat

    private static let gap = CGFloat(2)

    var body: some View {
        let strip = model.layout(
            maximumVisible: HubTabStrip.visibleCapacity(
                tabCount: model.allTabIDs.count,
                wingWidth: Double(wingWidth),
                tabWidth: Double(HolzBarTheme.Hub.tabSize.width),
                gap: Double(Self.gap)
            )
        )
        HStack(spacing: Self.gap) {
            ForEach(strip.visible, id: \.self) { id in
                tab(id, isSelected: id == strip.selected)
            }
            if !strip.overflow.isEmpty {
                moreMenu(strip.overflow)
            }
        }
        .frame(width: wingWidth, height: rowHeight, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func tab(_ id: String, isSelected: Bool) -> some View {
        let tint = tint(of: id)
        return Button {
            model.select(id)
        } label: {
            Image(systemName: symbol(of: id))
                .font(HolzBarTheme.Hub.tabSymbolFont)
                .foregroundStyle(isSelected ? tint.color : HolzBarTheme.Hub.idleTabSymbol)
                .frame(width: HolzBarTheme.Hub.tabSize.width, height: HolzBarTheme.Hub.tabSize.height)
                .background(
                    isSelected ? tint.color.opacity(HolzBarTheme.Hub.selectedTabFillOpacity) : HolzBarTheme.Hub.idleTabFill,
                    in: HolzBarTheme.shape(HolzBarTheme.Hub.tabRadius)
                )
                .frame(height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title(of: id))
        .accessibilityLabel(title(of: id))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func moreMenu(_ overflow: [String]) -> some View {
        Menu {
            ForEach(overflow, id: \.self) { id in
                Button {
                    model.select(id)
                } label: {
                    Label(title(of: id), systemImage: symbol(of: id))
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .accessibilityHidden(true)
                .font(HolzBarTheme.Hub.tabSymbolFont)
                .foregroundStyle(HolzBarTheme.Hub.idleTabSymbol)
                .frame(width: HolzBarTheme.Hub.tabSize.width, height: HolzBarTheme.Hub.tabSize.height)
                .background(HolzBarTheme.Hub.idleTabFill, in: HolzBarTheme.shape(HolzBarTheme.Hub.tabRadius))
                .frame(height: rowHeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
        .accessibilityLabel(Text("More"))
    }

    // MARK: What a tab shows

    private func symbol(of id: String) -> String {
        if id == HubTabStrip.overviewID {
            return "square.grid.2x2"
        }
        return ModuleCatalog.all.first { $0.id == id }?.symbol ?? "square"
    }

    private func title(of id: String) -> LocalizedStringKey {
        if id == HubTabStrip.overviewID {
            return "Overview"
        }
        return LocalizedStringKey(ModuleCatalog.all.first { $0.id == id }?.titleKey ?? id)
    }

    private func tint(of id: String) -> HubTint {
        model.runtimes.first { $0.moduleID == id }?.tint ?? .accent
    }
}
