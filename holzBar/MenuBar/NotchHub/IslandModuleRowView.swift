//
//  IslandModuleRowView.swift
//  holzBar
//

import SwiftUI

/// The island's row of module buttons: the Overview and every enabled module, each one round
/// button, in one row at the bottom of the island (concept section 10b).
///
/// The row never has a More menu. ``HubModuleRow`` decides the buttons' size and whether the row
/// scrolls: only when even the smallest buttons do not fit the widest hub does the row scroll
/// sideways, with the selected button kept in view. A button's name and symbol come only from the
/// module catalogue (or the fixed Overview), never from a module's own text. The whole row is one
/// accessibility group; the arrow keys of the island step through its buttons.
struct IslandModuleRowView: View {
    let model: NotchHubModel
    let fit: HubModuleRow.Fit

    var body: some View {
        Group {
            if fit.scrolls {
                scrollingRow
            } else {
                buttons
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Notch hub modules"))
    }

    // MARK: Layout

    private var buttons: some View {
        HStack(spacing: HolzBarTheme.Island.buttonGap) {
            ForEach(model.allTabIDs, id: \.self) { id in
                button(for: id)
            }
        }
    }

    /// A row that does not fit even at the smallest size: it scrolls, the selected button in view.
    private var scrollingRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                buttons
            }
            .scrollIndicators(.hidden)
            .onAppear {
                proxy.scrollTo(model.selectedID, anchor: .center)
            }
            .onChange(of: model.selectedID) { _, selected in
                withAnimation(HolzBarTheme.Motion.islandSwitch) {
                    proxy.scrollTo(selected, anchor: .center)
                }
            }
        }
    }

    // MARK: One button

    private func button(for id: String) -> some View {
        let isSelected = id == model.selectedID
        let size = CGFloat(fit.buttonSize)
        return Button {
            model.select(id)
        } label: {
            Image(systemName: symbol(of: id))
                .font(HolzBarTheme.Island.buttonSymbolFont)
                .foregroundStyle(isSelected ? HolzBarTheme.Island.buttonSelectedSymbol : HolzBarTheme.Island.buttonIdleSymbol)
                .frame(width: size, height: size)
                .background(
                    isSelected ? HolzBarTheme.Island.buttonSelectedFill : HolzBarTheme.Island.buttonIdleFill,
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .id(id)
        .help(title(of: id))
        .accessibilityLabel(title(of: id))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: What a button shows

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
}
