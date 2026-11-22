// P2 probe of phase 93: what camera cutout does each display have, and does it look like a notch
// or like Apple's Dynamic Island? Read-only: public AppKit and Darwin calls only, no permission,
// no network, no private API, nothing is changed.
//
// Run it (the OLED MacBook Pro with the Dynamic Island is the Mac this was written for; any Mac
// prints its own displays):
//
//   swift Scripts/macos27/cutout-probe.swift 2>&1 | tee ~/Desktop/cutout.txt
//
// It prints the model and the macOS version, then one block per display: the display number,
// whether it is built in, its frame, its visible frame, the top safe area, the width of the areas
// left and right of the camera cutout, the cutout width (display width - left area - right area),
// the ratio cutout width / top safe area and a classification. The classification mirrors
// DisplayCutout.classify and the D-03 heuristic of phase 93:
//
//   no auxiliary areas or a top safe area of 0   none
//   ratio below 3                                island (Apple's Dynamic Island, about 59 x 40)
//   otherwise                                    notch (about 185 x 32)
import AppKit

func model() -> String {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    guard size > 0 else { return "unknown" }
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.model", &buffer, &size, nil, 0)
    return String(cString: buffer)
}

func number(_ value: CGFloat) -> String {
    let rounded = (Double(value) * 10).rounded() / 10
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    return String(format: "%.1f", rounded)
}

func area(_ rect: NSRect?) -> String {
    guard let rect, rect.width > 0 else { return "none" }
    return number(rect.width)
}

func classification(safeTop: CGFloat, left: NSRect?, right: NSRect?, width: CGFloat) -> (String, CGFloat?, Double?) {
    guard safeTop > 0, let left, let right, left.width > 0, right.width > 0 else {
        return ("none", nil, nil)
    }
    let cutoutWidth = width - left.width - right.width
    guard cutoutWidth > 0 else { return ("none", nil, nil) }
    let ratio = Double(cutoutWidth / safeTop)
    return (ratio < 3 ? "island" : "notch", cutoutWidth, ratio)
}

print("model: \(model())")
print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")

for screen in NSScreen.screens {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    let displayID = (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    let frame = screen.frame
    let visible = screen.visibleFrame
    let safeTop = screen.safeAreaInsets.top
    let result = classification(
        safeTop: safeTop,
        left: screen.auxiliaryTopLeftArea,
        right: screen.auxiliaryTopRightArea,
        width: frame.width
    )
    print("")
    print("display: \(displayID)")
    print("built-in: \(CGDisplayIsBuiltin(displayID) != 0 ? "yes" : "no")")
    print("frame: \(number(frame.width)) x \(number(frame.height))")
    print("visibleFrame: \(number(visible.width)) x \(number(visible.height))")
    print("safe top: \(number(safeTop))")
    print("left area: \(area(screen.auxiliaryTopLeftArea))")
    print("right area: \(area(screen.auxiliaryTopRightArea))")
    if let cutoutWidth = result.1, let ratio = result.2 {
        print("cutout width: \(number(cutoutWidth))")
        print("ratio: \(String(format: "%.2f", ratio))")
    } else {
        print("cutout width: none")
        print("ratio: none")
    }
    print("classification: \(result.0)")
}
