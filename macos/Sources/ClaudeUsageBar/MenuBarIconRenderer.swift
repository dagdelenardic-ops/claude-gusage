import AppKit

private let labelWidth: CGFloat = 14
private let barWidth: CGFloat = 24
private let barHeight: CGFloat = 5
private let rowGap: CGFloat = 3
private let labelGap: CGFloat = 2
private let cornerRadius: CGFloat = 2
private let logoSize: CGFloat = 12
private let logoGap: CGFloat = 2
private let barsWidth: CGFloat = labelWidth + labelGap + barWidth + 2
private let iconWidth: CGFloat = logoSize + logoGap + barsWidth
private let iconHeight: CGFloat = 18
private let fontSize: CGFloat = 8

private let labelFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)

/// Label sizes are colour-independent, so we can cache the geometry once and
/// build the (appearance-tinted) attributed string at draw time.
private let labelSizes: [String: NSSize] = {
    var result = [String: NSSize]()
    for label in ["5h", "7d"] {
        let str = NSAttributedString(string: label, attributes: [.font: labelFont])
        result[label] = str.size()
    }
    return result
}()

/// Monochrome ink for text / logo / track — follows the menu bar appearance so
/// it stays legible on both light and dark menu bars.
private func menuBarInk() -> NSColor {
    let isDark = NSApp?.effectiveAppearance
        .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    return isDark ? .white : .black
}

/// Traffic-light fill by usage: green while comfortable, yellow past 50%,
/// red past 75%.
private func usageFillColor(_ pct: Double) -> NSColor {
    switch pct {
    case ..<0.50: return .systemGreen
    case 0.50..<0.75: return .systemYellow
    default: return .systemRed
    }
}

private func drawRow(
    label: String,
    ink: NSColor,
    barX: CGFloat,
    barY: CGFloat,
    labelX: CGFloat,
    drawBarFill: (CGFloat, CGFloat) -> Void
) {
    if let size = labelSizes[label] {
        let str = NSAttributedString(
            string: label,
            attributes: [.font: labelFont, .foregroundColor: ink]
        )
        let labelY = barY + (barHeight - size.height) / 2
        str.draw(at: NSPoint(x: labelX + labelWidth - size.width, y: labelY))
    }
    drawBarFill(barX, barY)
}

func renderIcon(pct5h: Double, pct7d: Double) -> NSImage {
    let ink = menuBarInk()
    let image = NSImage(size: NSSize(width: iconWidth, height: iconHeight), flipped: true) { _ in
        let offset = logoSize + logoGap
        let barX = offset + labelWidth + labelGap
        let topY = (iconHeight - barHeight * 2 - rowGap) / 2
        let bottomY = topY + barHeight + rowGap

        drawClaudeLogo(x: 0, y: (iconHeight - logoSize) / 2, size: logoSize, tint: ink)

        drawRow(label: "5h", ink: ink, barX: barX, barY: topY, labelX: offset) { x, y in
            drawBar(x: x, y: y, width: barWidth, height: barHeight, cornerRadius: cornerRadius, pct: pct5h, ink: ink)
        }
        drawRow(label: "7d", ink: ink, barX: barX, barY: bottomY, labelX: offset) { x, y in
            drawBar(x: x, y: y, width: barWidth, height: barHeight, cornerRadius: cornerRadius, pct: pct7d, ink: ink)
        }
        return true
    }
    // Not a template: the bars carry their own usage colours.
    image.isTemplate = false
    return image
}

func renderUnauthenticatedIcon() -> NSImage {
    let ink = menuBarInk()
    let image = NSImage(size: NSSize(width: iconWidth, height: iconHeight), flipped: true) { _ in
        let offset = logoSize + logoGap
        let barX = offset + labelWidth + labelGap
        let topY = (iconHeight - barHeight * 2 - rowGap) / 2
        let bottomY = topY + barHeight + rowGap

        drawClaudeLogo(x: 0, y: (iconHeight - logoSize) / 2, size: logoSize, tint: ink)

        drawRow(label: "5h", ink: ink, barX: barX, barY: topY, labelX: offset) { x, y in
            drawDashedBar(x: x, y: y, width: barWidth, height: barHeight, cornerRadius: cornerRadius, ink: ink)
        }
        drawRow(label: "7d", ink: ink, barX: barX, barY: bottomY, labelX: offset) { x, y in
            drawDashedBar(x: x, y: y, width: barWidth, height: barHeight, cornerRadius: cornerRadius, ink: ink)
        }
        return true
    }
    image.isTemplate = false
    return image
}

// MARK: - Bar drawing

private func drawBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, cornerRadius: CGFloat, pct: Double, ink: NSColor) {
    let bgRect = NSRect(x: x, y: y, width: width, height: height)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
    ink.withAlphaComponent(0.25).setFill()
    bgPath.fill()

    let clampedPct = max(0, min(1, pct))
    if clampedPct > 0 {
        let fillWidth = width * clampedPct
        let fillRect = NSRect(x: x, y: y, width: fillWidth, height: height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: cornerRadius, yRadius: cornerRadius)
        usageFillColor(clampedPct).setFill()
        fillPath.fill()
    }
}

private func drawDashedBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, cornerRadius: CGFloat, ink: NSColor) {
    let rect = NSRect(x: x, y: y, width: width, height: height)
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    ink.withAlphaComponent(0.25).setStroke()
    path.lineWidth = 1
    let dashPattern: [CGFloat] = [2, 2]
    path.setLineDash(dashPattern, count: 2, phase: 0)
    path.stroke()
}

// MARK: - Claude logo (pre-rendered 512px template PNG)

private let claudeLogoImage: NSImage? = {
    if let bundle = claudeUsageBarResourceBundle(),
       let png = bundle.url(forResource: "claude-logo", withExtension: "png") {
        return NSImage(contentsOf: png)
    }
    return nil
}()

private func drawClaudeLogo(x: CGFloat, y: CGFloat, size: CGFloat, tint: NSColor) {
    guard let logo = claudeLogoImage else { return }
    let rect = NSRect(x: x, y: y, width: size, height: size)
    logo.draw(in: rect)
    // The logo PNG is a solid glyph; tint it to the menu bar ink so it stays
    // visible in both light and dark menu bars (no template auto-tint anymore).
    tint.setFill()
    rect.fill(using: .sourceAtop)
}
