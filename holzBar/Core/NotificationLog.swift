//
//  NotificationLog.swift
//  holzBar
//

import Foundation

/// One notification banner as the Notifications module lists it.
nonisolated struct NotificationRecord: Identifiable, Equatable, Sendable {
    /// A new identifier for the row; it says nothing about the notification.
    let id: UUID
    /// The name of the app, when the banner stated it.
    let app: String?
    /// The title.
    let title: String?
    /// The text.
    let body: String?
    /// When holzBar read the banner.
    let received: Date
    /// The identifier macOS gave the banner, used to notice the same banner again.
    let bannerID: String?
}

/// The list of notifications the Notifications module shows, and its privacy rules.
///
/// This is the only place the text of a notification lives. It is a value held in memory by
/// the running module: it is never written to disk, a log, an export or the network, and it is
/// emptied when the module or the hub goes off. It keeps at most ``maximumRecords``, the newest
/// first; the oldest leaves when a new one arrives.
nonisolated struct NotificationLog: Equatable, Sendable {
    /// What ``record(_:now:excludedApps:isPresenting:makeID:)`` did with a draft.
    enum Outcome: Equatable, Sendable {
        /// The draft is now the newest record.
        case recorded
        /// The screen is mirrored or shared, so nothing was kept.
        case presenting
        /// The draft had neither a title nor a body.
        case empty
        /// The draft is from an app on the exclusion list.
        case excluded
        /// The draft repeats the newest record, or a banner already recorded.
        case duplicate
    }

    /// The most records the log keeps.
    static let maximumRecords = 20

    /// How many seconds apart the same app, title and body count as one record.
    static let duplicateWindow: TimeInterval = 2

    /// How many banner identifiers are remembered to recognise a banner that fires several
    /// events. They are random identifiers of macOS and hold no text.
    private static let maximumRememberedBanners = 40

    /// The records, the newest first.
    private(set) var records = [NotificationRecord]()

    /// The identifiers of the banners recorded last, the newest last.
    private var rememberedBanners = [String]()

    init() {}

    /// Applies the privacy rules to a draft and keeps it when they allow.
    ///
    /// The rules apply in this order, and the first that fits decides: the screen is mirrored
    /// or shared (`presenting`, nothing is kept); the draft has neither a title nor a body
    /// (`empty`); its app is on the exclusion list, compared trimmed and without regard to case
    /// (`excluded`); it has the app, title and body of the newest record and arrives less than
    /// ``duplicateWindow`` seconds after it, or its banner identifier is one already recorded
    /// (`duplicate`). Otherwise the record goes in front.
    @discardableResult
    mutating func record(
        _ draft: NotificationBannerParser.Draft,
        now: Date,
        excludedApps: Set<String>,
        isPresenting: Bool,
        makeID: () -> UUID
    ) -> Outcome {
        if isPresenting {
            return .presenting
        }
        if draft.title == nil, draft.body == nil {
            return .empty
        }
        if let app = draft.app, Self.contains(excludedApps, app) {
            return .excluded
        }
        if isDuplicate(draft, now: now) {
            return .duplicate
        }
        records.insert(
            NotificationRecord(
                id: makeID(),
                app: draft.app,
                title: draft.title,
                body: draft.body,
                received: now,
                bannerID: draft.bannerID
            ),
            at: 0
        )
        if records.count > Self.maximumRecords {
            records.removeLast(records.count - Self.maximumRecords)
        }
        if let bannerID = draft.bannerID {
            rememberedBanners.append(bannerID)
            if rememberedBanners.count > Self.maximumRememberedBanners {
                rememberedBanners.removeFirst(rememberedBanners.count - Self.maximumRememberedBanners)
            }
        }
        return .recorded
    }

    /// Erases the record with the identifier at once; an unknown identifier changes nothing.
    mutating func remove(_ id: NotificationRecord.ID) {
        records.removeAll { $0.id == id }
    }

    /// Erases every record of the app, compared trimmed and without regard to case.
    mutating func removeAll(fromApp app: String) {
        let key = Self.key(app)
        records.removeAll { record in
            record.app.map { Self.key($0) == key } ?? false
        }
    }

    /// Erases every record at once.
    mutating func removeAll() {
        records.removeAll()
    }

    private func isDuplicate(_ draft: NotificationBannerParser.Draft, now: Date) -> Bool {
        if let bannerID = draft.bannerID, rememberedBanners.contains(bannerID) {
            return true
        }
        guard let newest = records.first else {
            return false
        }
        let age = now.timeIntervalSince(newest.received)
        return age >= 0
            && age < Self.duplicateWindow
            && newest.app == draft.app
            && newest.title == draft.title
            && newest.body == draft.body
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func contains(_ names: Set<String>, _ name: String) -> Bool {
        let wanted = key(name)
        return names.contains { key($0) == wanted }
    }
}
