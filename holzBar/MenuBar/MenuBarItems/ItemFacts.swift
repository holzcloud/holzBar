//
//  ItemFacts.swift
//  holzBar
//

import AppKit

/// Builds the static facts about a menu bar item that Tidy Up and the search sort by: its
/// identity key, namespace and title, the category its application declares, and the section it
/// is in.
///
/// The facts are local and static: the application's category is read from the `Info.plist` of
/// its bundle on this Mac, once per application, and nothing is observed or counted. A reader
/// lives only as long as the sheet or the panel that made it; what it learned is dropped with it
/// and nothing is kept or sent.
@MainActor
struct ItemFactsReader {
    /// The category each application declares, by the path of its bundle. An application that
    /// declares none is kept as `nil`, so its bundle is not read again.
    private var applicationCategories = [String: String?]()

    /// The facts of an item in a section.
    mutating func classifiable(
        _ item: MenuBarItem,
        in section: MenuBarSection.Name,
        using itemManager: MenuBarItemManager
    ) -> ClassifiableItem {
        ClassifiableItem(
            key: itemManager.identityKey(for: item),
            namespace: item.tag.namespace.description,
            title: item.tag.title,
            applicationCategory: applicationCategory(of: item),
            section: section.profileIndex,
            // A widget is holzBar's own item: never proposed (D-25).
            isOwnItem: item.tag.namespace == .holzBar
        )
    }

    /// The `LSApplicationCategoryType` of the item's application, read from its bundle.
    private mutating func applicationCategory(of item: MenuBarItem) -> String? {
        guard let url = item.sourceApplication?.bundleURL else {
            return nil
        }
        if let known = applicationCategories[url.path] {
            return known
        }
        let category = Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        applicationCategories[url.path] = category
        return category
    }
}
