//
//  ControlItemImageSet.swift
//  holzBar
//

/// A named set of images that are used by control items.
///
/// An image set contains images for a control item in both the hidden and visible states.
struct ControlItemImageSet: Codable, Hashable, Identifiable {
    enum Name: String, Codable, Hashable {
        case arrow = "Arrow"
        case chevron = "Chevron"
        case logo = "holzBar"
        case door = "Door"
        case dot = "Dot"
        case ellipsis = "Ellipsis"
        case iceCube = "Ice Cube"
        case sunglasses = "Sunglasses"
        case custom = "Custom"

        /// The name the logo image set was stored under before the app
        /// was renamed holzBar, decoded as ``logo``.
        private static let previousLogoName = "holzIce"

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            if rawValue == Self.previousLogoName {
                self = .logo
            } else if let name = Name(rawValue: rawValue) {
                self = name
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown image set name \(rawValue)"
                )
            }
        }
    }

    let name: Name
    let hidden: ControlItemImage
    let visible: ControlItemImage

    var id: Int { hashValue }

    init(name: Name, hidden: ControlItemImage, visible: ControlItemImage) {
        self.name = name
        self.hidden = hidden
        self.visible = visible
    }

    init(name: Name, image: ControlItemImage) {
        self.init(name: name, hidden: image, visible: image)
    }
}

extension ControlItemImageSet {
    /// The default image set for the holzBar icon: the ice cube with its
    /// chevron, standing on the plank, from the app icon.
    static let defaultHolzBarIcon = ControlItemImageSet(
        name: .logo,
        hidden: .catalog("LogoFill"),
        visible: .catalog("LogoStroke")
    )

    /// The image sets that the user can choose to display in the holzBar icon.
    static let userSelectableHolzBarIcons = [
        ControlItemImageSet(
            name: .arrow,
            hidden: .symbol("arrowshape.left.fill"),
            visible: .symbol("arrowshape.right.fill")
        ),
        ControlItemImageSet(
            name: .chevron,
            hidden: .symbol("chevron.left"),
            visible: .symbol("chevron.right")
        ),
        ControlItemImageSet(
            name: .logo,
            hidden: .catalog("LogoFill"),
            visible: .catalog("LogoStroke")
        ),
        ControlItemImageSet(
            name: .door,
            hidden: .symbol("door.left.hand.closed"),
            visible: .symbol("door.left.hand.open")
        ),
        ControlItemImageSet(
            name: .dot,
            hidden: .catalog("DotFill"),
            visible: .catalog("DotStroke")
        ),
        ControlItemImageSet(
            name: .ellipsis,
            hidden: .catalog("EllipsisFill"),
            visible: .catalog("EllipsisStroke")
        ),
        ControlItemImageSet(
            name: .iceCube,
            hidden: .catalog("IceCubeStroke"),
            visible: .catalog("IceCubeFill")
        ),
        ControlItemImageSet(
            name: .sunglasses,
            hidden: .symbol("sunglasses.fill"),
            visible: .symbol("sunglasses")
        ),
    ]
}
