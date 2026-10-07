//
//  NotchCover27.swift
//  holzBar
//

import CoreGraphics

/// Keeps holzBar's icon out from under the notch on macOS 27.
///
/// On a crowded notched bar, macOS 27 can lay holzBar's own icon out under the notch, where
/// nobody can click it (Thaw #1195, #1153). Concealing visible apps to the right of the icon
/// moves it right by their width; holzBar conceals the nearest ones until the icon clears the
/// notch, for as long as the bar stays as it is. That concealment is transient and never
/// written to the saved layout.
nonisolated enum NotchCover27 {
    /// An app with an item drawn on the bar.
    typealias App = (bundleID: String, frame: CGRect)

    /// The visible apps to conceal, nearest to the icon first, so the icon clears the notch.
    ///
    /// The icon has to move right until its left edge passes the notch's right edge. The apps
    /// right of the icon are taken from the icon outwards (an app with several items counts
    /// once, with all their widths) until their widths add up to that; when they cannot, all
    /// of them are returned.
    ///
    /// - Parameters:
    ///   - iconFrame: The frame of holzBar's icon.
    ///   - visibleApps: The items drawn on the bar, with their apps.
    ///   - notchSpan: The horizontal span the notch covers.
    ///   - concealed: The apps already concealed.
    ///   - ownBundleID: holzBar's bundle identifier.
    /// - Returns: The apps to conceal, or none when the icon is clear of the notch.
    static func appsToConceal(
        iconFrame: CGRect,
        visibleApps: [App],
        notchSpan: ClosedRange<CGFloat>,
        concealed: Set<String>,
        ownBundleID: String
    ) -> [String] {
        guard iconFrame.maxX > notchSpan.lowerBound, iconFrame.minX < notchSpan.upperBound else {
            return []
        }
        let needed = notchSpan.upperBound - iconFrame.minX
        var order = [String]()
        var widths = [String: CGFloat]()
        for app in visibleApps.sorted(by: { $0.frame.minX < $1.frame.minX }) {
            guard
                app.frame.minX >= iconFrame.midX,
                app.bundleID != ownBundleID,
                !concealed.contains(app.bundleID)
            else {
                continue
            }
            if widths[app.bundleID] == nil {
                order.append(app.bundleID)
            }
            widths[app.bundleID, default: 0] += app.frame.width
        }
        var freed: CGFloat = 0
        var answer = [String]()
        for bundleID in order {
            answer.append(bundleID)
            freed += widths[bundleID, default: 0]
            if freed >= needed {
                break
            }
        }
        return answer
    }

    /// The concealed sets of the assertions with the given apps concealed as well.
    ///
    /// The apps concealed together are the intersection of the sets, so the extra apps join
    /// every set; with no assertion they make one of their own.
    static func adding(_ apps: Set<String>, to sets: [Set<String>]) -> [Set<String>] {
        guard !apps.isEmpty else {
            return sets
        }
        guard !sets.isEmpty else {
            return [apps]
        }
        return sets.map { $0.union(apps) }
    }

    /// Whether the apps concealed for the notch are worth working out again after the
    /// sections' concealment changed from `before` to `after`.
    ///
    /// Only a change that conceals an app the sections did not conceal before can free room
    /// on the bar. One that conceals less leaves it at least as crowded: clearing then would
    /// show the apps concealed for the notch with the released ones, only to conceal them
    /// again a settled read later.
    static func sectionsMayFreeRoom(before: Set<String>, after: Set<String>) -> Bool {
        !after.isSubset(of: before)
    }
}
