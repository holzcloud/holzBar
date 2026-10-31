//
//  CalendarColorDot.swift
//  holzBar
//

import SwiftUI

/// A small dot in a calendar's own colour.
///
/// The colour comes from the user's calendar, not from the theme, so this is the one place a
/// colour is built from data.
struct CalendarColorDot: View {
    let color: CalendarColor

    var body: some View {
        Circle()
            .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue))
            .frame(width: 8, height: 8)
            // Decorative: the event's title says what the row is.
            .accessibilityHidden(true)
    }
}

#Preview("CalendarColorDot") {
    CalendarColorDot(color: CalendarColor(red: 0.2, green: 0.5, blue: 0.9))
        .padding()
        .background(HolzBarTheme.Palette.ground)
}
