import SwiftUI

/// One Space's crest as the switcher draws it, or its dot when Space icons
/// are dots.
///
/// The shared artwork preserves the crest's original colors and layered badge
/// in both the compact desktop track and the expanded touch segments.
struct BrowserSpacePickerIcon: View {
    private static let slateSymbolColor = BrandColor(red: 66.0 / 255, green: 82.0 / 255, blue: 106.0 / 255)

    let space: BrowserSpaceIdentity
    let metrics: BrowserSpacePickerMetrics
    /// The Spaces the switcher shades its dots among, or nil to draw the
    /// Space's crest.
    var dots: BrowserSpaceDot.Field? = nil
    var symbolBackgrounds: [Color] = []
    var inactiveSymbolTone: BrowserSpaceForegroundTone? = nil

    @Environment(\.self) private var environment

    var body: some View {
        if let dots {
            BrowserSpaceDot(
                spaceID: space.id, field: dots, isLocked: space.requiresAuthentication,
                scale: metrics.iconSize / BrowserSpacePickerMetrics.pointer.iconSize
            )
            // The dot takes its whole segment, so a tab drops on it easily.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .transition(.opacity)
        } else {
            BrowserSpaceSymbolArtwork(identity: readableArtwork, size: metrics.iconSize, lockSize: metrics.lockSize)
                .padding(metrics.iconPadding)
                .transition(.opacity)
        }
    }

    private var readableArtwork: BrowserSpaceIdentity {
        guard let symbolColor else { return space }
        var branding = space.branding
        branding.symbolColor = symbolColor
        branding.symbolGradient = nil
        return space.wearing(branding, symbol: space.symbol, name: space.name)
    }

    private var symbolColor: BrandColor? {
        guard !symbolBackgrounds.isEmpty,
            case .symbol(let name) = BrowserSpaceIdentityArtwork(space),
            BrowserIconSymbol.emoji(from: name) == nil
        else { return nil }
        let accent = space.branding.accentFill.colors
        let minimumContrast = 3.0
        guard
            inactiveSymbolTone != nil
                || accent.contains(where: { color in
                    symbolBackgrounds.contains {
                        color.color.contrastRatio(over: $0, environment: environment) < minimumContrast
                    }
                })
        else { return nil }

        // ponytail: checks palette samples, not individual pixels during swipes or over grain.
        let black = symbolBackgrounds.map { Color.black.contrastRatio(over: $0, environment: environment) }
        let white = symbolBackgrounds.map { Color.white.contrastRatio(over: $0, environment: environment) }
        guard let blackMinimum = black.min(), let whiteMinimum = white.min() else { return nil }
        if inactiveSymbolTone == .light, whiteMinimum >= minimumContrast {
            return BrandColor(red: 1, green: 1, blue: 1)
        }
        if (inactiveSymbolTone == .dark && blackMinimum >= minimumContrast) || blackMinimum >= whiteMinimum {
            let slate = Self.slateSymbolColor
            return symbolBackgrounds.allSatisfy {
                slate.color.contrastRatio(over: $0, environment: environment) >= minimumContrast
            } ? slate : BrandColor(red: 0, green: 0, blue: 0)
        }
        return BrandColor(red: 1, green: 1, blue: 1)
    }
}
