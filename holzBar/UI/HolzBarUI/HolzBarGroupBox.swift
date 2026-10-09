//
//  HolzBarGroupBox.swift
//  holzBar
//

import SwiftUI

struct HolzBarGroupBox<Header: View, Content: View, Footer: View>: View {
    private let header: Header
    private let content: Content
    private let footer: Footer
    private let padding: EdgeInsets

    private var backgroundShape: some InsettableShape {
        HolzBarTheme.shape(HolzBarTheme.Radius.card)
    }

    init(
        padding: EdgeInsets = .holzBarGroupBoxDefaultPadding,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.padding = padding
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    init(
        padding: CGFloat,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.init(padding: EdgeInsets(all: padding)) {
            header()
        } content: {
            content()
        } footer: {
            footer()
        }
    }

    init(
        padding: EdgeInsets = .holzBarGroupBoxDefaultPadding,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) where Header == EmptyView {
        self.init(padding: padding) {
            EmptyView()
        } content: {
            content()
        } footer: {
            footer()
        }
    }

    init(
        padding: CGFloat,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) where Header == EmptyView {
        self.init(padding: padding) {
            EmptyView()
        } content: {
            content()
        } footer: {
            footer()
        }
    }

    init(
        padding: EdgeInsets = .holzBarGroupBoxDefaultPadding,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.init(padding: padding) {
            header()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        padding: CGFloat,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.init(padding: padding) {
            header()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        padding: EdgeInsets = .holzBarGroupBoxDefaultPadding,
        @ViewBuilder content: () -> Content
    ) where Header == EmptyView, Footer == EmptyView {
        self.init(padding: padding) {
            EmptyView()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        padding: CGFloat,
        @ViewBuilder content: () -> Content
    ) where Header == EmptyView, Footer == EmptyView {
        self.init(padding: padding) {
            EmptyView()
        } content: {
            content()
        } footer: {
            EmptyView()
        }
    }

    init(
        _ title: LocalizedStringKey,
        padding: EdgeInsets = .holzBarGroupBoxDefaultPadding,
        @ViewBuilder content: () -> Content
    ) where Header == Text, Footer == EmptyView {
        self.init(padding: padding) {
            Text(title).font(.headline)
        } content: {
            content()
        }
    }

    init(
        _ title: LocalizedStringKey,
        padding: CGFloat,
        @ViewBuilder content: () -> Content
    ) where Header == Text, Footer == EmptyView {
        self.init(padding: padding) {
            Text(title).font(.headline)
        } content: {
            content()
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            header
                .accessibilityAddTraits(.isHeader)
                .padding([.top, .leading], 8)
                .padding(.bottom, 2)

            contentStack
                .padding(padding)
                .background {
                    backgroundShape
                        .fill(HolzBarTheme.Palette.groundElevated)
                        .overlay {
                            backgroundShape.strokeBorder(
                                HolzBarTheme.Palette.stroke,
                                lineWidth: HolzBarTheme.Spacing.hairline
                            )
                        }
                }
                .containerShape(backgroundShape)

            footer
                .padding([.bottom, .leading], 8)
                .padding(.top, 2)
        }
        .focusSection()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var contentStack: some View {
        VStack { content }
    }
}

extension EdgeInsets {
    /// The default padding for a ``HolzBarGroupBox``.
    static let holzBarGroupBoxDefaultPadding = EdgeInsets(all: 12)
}
