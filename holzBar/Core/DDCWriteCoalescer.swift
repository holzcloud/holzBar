//
//  DDCWriteCoalescer.swift
//  holzBar
//

import Foundation

/// Keeps the writes to one control of one monitor to one at a time, the latest value winning.
///
/// A slider drag produces values faster than a monitor takes them (a write blocks for tens of
/// milliseconds). The first value submitted while idle starts the single writer; values that
/// arrive while it writes replace each other, and the writer takes whatever is latest when it
/// asks for the next one. The value does no writing and no waiting.
nonisolated struct DDCWriteCoalescer: Equatable, Sendable {
    private var pending: UInt16?
    private var isWriting = false

    /// Offers a value. Returns `true` when no writer is running, which means the caller starts
    /// one; it then asks ``next()`` until that returns `nil`. Returns `false` while a writer
    /// runs; the value waits for it and replaces any value that waited before.
    mutating func submit(_ value: UInt16) -> Bool {
        pending = value
        guard !isWriting else {
            return false
        }
        isWriting = true
        return true
    }

    /// The latest value not written yet, taken off the line, or `nil` when there is none, which
    /// ends the writer: a later ``submit(_:)`` starts a new one.
    mutating func next() -> UInt16? {
        guard let value = pending else {
            isWriting = false
            return nil
        }
        pending = nil
        return value
    }
}
