import SwiftUI

/// A stable-height scroll lane with explicit controls for mouse-only scrolling.
struct BrowserSpaceSwitcherCompactPicker: View {
    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID
    var reorderState: BrowserSidebarReorderState? = nil
    let metrics: BrowserSpacePickerMetrics
    let selectSpace: (UUID) -> Void
    let allocation: BrowserSpaceSwitcherCompactAllocation
    var moveSpace: ((UUID, UUID) -> Void)? = nil
    /// The picker's style, before its corners take the tabs' radius.
    var style: CrestSpaceIconPickerStyle = .compact

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.self) private var environment
    @Environment(\.spacePagerPresentation) private var spacePagerPresentation
    private let appearance = BrowserDeviceAppearanceStore.shared
    @State private var overflow = BrowserSpacePickerOverflow()
    @State private var viewport = CGRect.zero

    /// The picker's style with corners as round as the tabs' and pins'.
    private var shapedStyle: CrestSpaceIconPickerStyle {
        style.rounded(CGFloat(appearance.sidebarCornerRadius))
    }

    var body: some View {
        ScrollViewReader { reader in
            HStack(spacing: 0) {
                if allocation.usesOverflow {
                    overflowButton(forward: false, reader: reader)
                }
                track
                if allocation.usesOverflow {
                    overflowButton(forward: true, reader: reader)
                }
            }
            .frame(width: allocation.pickerViewportWidth)
            .task(id: selectedSpaceID) {
                await Task.yield()
                revealSelection(reader, animated: true)
            }
            .onChange(of: allocation.pickerViewportWidth) {
                revealSelection(reader, animated: false)
            }
            .onChange(of: spaces.map(\.id)) {
                // Customization drags have already scrolled to their drop slot.
                // Keep that viewport; only an explicit selection should recenter it.
                if moveSpace == nil {
                    revealSelection(reader, animated: false)
                }
            }
        }
        .accessibilitySortPriority(BrowserSpaceSwitcherLayout.pickerAccessibilityPriority)
    }

    private var track: some View {
        let style = shapedStyle
        let showsDots = appearance.spaceIcons.showsDots
        let dots =
            showsDots
            ? BrowserSpaceDot.Field(
                profiles: Dictionary(spaces.map { ($0.id, $0.profileID) }, uniquingKeysWith: { first, _ in first }),
                selectedSpaceID: selectedSpaceID) : nil
        let tracksSelection = moveSpace == nil && spacePagerPresentation != nil
        let (symbolBackgrounds, inactiveTone) =
            showsDots ? ([:], nil) : symbolAppearance(tracksSelection: tracksSelection)
        return ScrollView(.horizontal) {
            CrestSpaceIconPicker(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID,
                selectSpace: selectSpace,
                style: style,
                accessibilityIdentifier: "space-switcher-picker",
                moveSpace: moveSpace,
                reorderViewport: viewport,
                selectionPresentation: moveSpace == nil ? spacePagerPresentation : nil,
                segmentSize: CGSize(width: segmentWidth, height: style.segmentHeight),
                drawsSurfaces: !showsDots
            ) { space in
                let inactiveSymbolTone = space.id == selectedSpaceID ? nil : inactiveTone
                if let reorderState {
                    BrowserSpacePickerSegment(
                        space: space, reorderState: reorderState, metrics: metrics,
                        visibleRegion: viewport.isEmpty ? nil : viewport, dots: dots,
                        symbolBackgrounds: symbolBackgrounds[space.id] ?? [], inactiveSymbolTone: inactiveSymbolTone
                    )
                } else {
                    BrowserSpacePickerIcon(
                        space: space, metrics: metrics, dots: dots,
                        symbolBackgrounds: symbolBackgrounds[space.id] ?? [],
                        inactiveSymbolTone: inactiveSymbolTone
                    )
                }
            }
            .frame(minWidth: allocation.scrollViewportWidth, alignment: .center)
        }
        // `.hidden` still reserves a legacy scrollbar on macOS. The flanking
        // buttons provide scrolling without requiring a horizontal gesture.
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(width: allocation.scrollViewportWidth, height: style.height)
        .clipShape(CrestSpaceIconPickerShape(style: style))
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            viewport = $0
        }
        .onScrollGeometryChange(for: BrowserSpacePickerOverflow.self) { geometry in
            BrowserSpacePickerOverflow(
                visibleRect: geometry.visibleRect,
                contentWidth: geometry.contentSize.width,
                spaceCount: spaces.count, segmentWidth: segmentWidth, style: style
            )
        } action: { _, value in
            overflow = value
        }
    }

    private func symbolAppearance(tracksSelection: Bool) -> ([UUID: [Color]], BrowserSpaceForegroundTone?) {
        guard let selectedIndex = spaces.firstIndex(where: { $0.id == selectedSpaceID }) else { return ([:], nil) }
        let branding = spaces[selectedIndex].branding
        var windowEnvironment = environment
        windowEnvironment.colorScheme = environment.deviceColorScheme ?? environment.colorScheme
        #if os(macOS)
            let sidebarBranding = branding.shown
        #else
            let sidebarBranding = branding
        #endif
        let sidebar = BrowserSpaceBannerBackground.colorSamples(
            branding: sidebarBranding, environment: windowEnvironment)
        let wellTone = CrestSpaceIconPickerTone.over(environment.colorScheme)
        let selectorTone =
            tracksSelection
            ? CrestSpaceIconPickerTone.over(branding.colorScheme(over: windowEnvironment.colorScheme)) : wellTone
        let outline = SpacePickerGroupOutline(profileIDs: spaces.map(\.profileID))
        let primary = outline.primary(of: selectedIndex)
        let groupTone: CrestSpaceIconPickerTone? =
            tracksSelection && outline.outlinesGroups && outline.isGrouped(selectedIndex)
            ? .over(spaces[primary].branding.colorScheme(over: windowEnvironment.colorScheme)) : nil

        let backgrounds = Dictionary(
            uniqueKeysWithValues: spaces.enumerated().map { index, space in
                let group = outline.primary(of: index) == primary ? groupTone : nil
                let backgrounds = wellTone.symbolBackgrounds(
                    over: sidebar, groupTone: group, selectorTone: index == selectedIndex ? selectorTone : nil)
                return (space.id, backgrounds)
            })
        return (backgrounds, sidebarBranding.foregroundTone(over: windowEnvironment.colorScheme))
    }

    private func overflowButton(forward: Bool, reader: ScrollViewProxy) -> some View {
        let targetIndex = forward ? overflow.nextIndex : overflow.previousIndex
        let title: LocalizedStringResource = forward ? "Show Next Spaces" : "Show Previous Spaces"
        return Button {
            guard let targetIndex, spaces.indices.contains(targetIndex) else { return }
            withAnimation(scrollAnimation) {
                reader.scrollTo(spaces[targetIndex].id, anchor: forward ? .leading : .trailing)
            }
        } label: {
            Image(systemName: forward ? "chevron.forward" : "chevron.backward")
                .font(.caption.weight(.semibold))
                .frame(
                    width: style.overflowButtonWidth,
                    height: style.height
                )
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .disabled(targetIndex == nil)
        .accessibilityLabel(Text(title))
        .help(Text(title))
        .accessibilityIdentifier(forward ? "space-picker-next" : "space-picker-previous")
    }

    private var segmentWidth: CGFloat {
        guard style.fillsSegments, !spaces.isEmpty else { return style.minimumSegmentWidth }
        return max(
            style.minimumSegmentWidth,
            (allocation.scrollViewportWidth - 2 * style.trackPadding) / CGFloat(spaces.count))
    }

    private var scrollAnimation: Animation? {
        CrestMotion.scrollAlignment.unlessReducingMotion(reduceMotion)
    }

    private func revealSelection(_ reader: ScrollViewProxy, animated: Bool) {
        // The native leaf follows the pager's tracking and release timeline.
        // A second scrollTo animation would lag that handoff.
        guard spacePagerPresentation == nil || moveSpace != nil else { return }
        guard
            let target = BrowserSpaceSwitcherLayout.compactScrollTarget(
                spaceIDs: spaces.map(\.id),
                selectedSpaceID: selectedSpaceID
            )
        else { return }
        withAnimation(animated ? scrollAnimation : nil) {
            reader.scrollTo(target, anchor: .center)
        }
    }
}
