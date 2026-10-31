//
//  HubTabStripView.swift
//  holzBar
//

import SwiftUI

/// One group of the Notch hub's icon row: the tabs of the left wing, or the tabs at the notch
/// side of the right wing.
///
/// The row spans both wings; ``HubTabStrip/row(moduleTabs:selected:leftWingWidth:rightWingWidth:rightReservedWidth:gap:)``
/// decides which tab sits in which group and how wide a tab is. The selected tab is tinted by
/// its module. Each tab is 24 points high to the eye, and its hit area is the whole height of
/// the top row. Where the row cannot fit even at its smallest tab width, the last place of the
/// right group (of the left group without a right wing) is a More menu.
struct HubTabStripView: View {
    let model: NotchHubModel
    /// The tabs of this group, in order.
    let ids: [String]
    /// The selected tab.
    let selected: String
    /// The width of one tab, the same across the whole row.
    let tabWidth: CGFloat
    /// The height of the top row.
    let rowHeight: CGFloat
    /// The tabs that did not fit, listed in a More menu after the tabs of this group. Empty
    /// where every tab has a place or where the other group holds the menu.
    var overflow: [String] = []

    var body: some View {
        HStack(spacing: HolzBarTheme.Hub.tabGap) {
            ForEach(ids, id: \.self) { id in
                tab(id, isSelected: id == selected)
            }
            if !overflow.isEmpty {
                moreMenu(overflow)
            }
        }
        .frame(height: rowHeight)
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
                .frame(width: tabWidth, height: HolzBarTheme.Hub.tabSize.height)
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
                .frame(width: tabWidth, height: HolzBarTheme.Hub.tabSize.height)
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
