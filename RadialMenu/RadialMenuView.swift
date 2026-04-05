//
//  RadialMenuView.swift
//  ponda
//
//  A fluid radial fan menu with proximity-based scaling,
//  long-press → hover → lock → adjust gesture flow,
//  Metal ripple feedback, and Liquid Glass aesthetic (iOS 26).
//
//  Gesture flow:
//    tap           → show manual-add sheet
//    long-press    → fan-out satellites with ripple burst
//    drag to hover → proximity scaling + haptic tick
//    hover & hold  → lock satellite, enter adjusting mode
//    slide ↕       → multiplier ×0.5 steps
//    slide ↔       → cancel (multiplier → 0)
//    release       → confirm entry (or cancel if multiplier == 0)
//
//  Dependencies: DS (DesignSystem), PondaViewModel, PondaItem,
//                ShaderLibrary.rippleColorBurst (Metal)
//

import SwiftUI
import Foundation

// MARK: - Constants

private enum RadialMenuConstants {
    static let radius: CGFloat = 96
    static let escapeDistance: CGFloat = 24
    static let startAngle: Double = -86
    static let stepAngle: Double = 40
    static let fabSize: CGFloat = 60
    static let satelliteNormalSize: CGFloat = 58
    static let satelliteActiveSize: CGFloat = 72
    static let magnetThreshold: CGFloat = 60
    static let scrimOpacity: Double = 0.8
    static let menuSpring = DS.Animation.menuPop
    static let scaleSpring = DS.Animation.snappy
    static let longPressDuration: Double = 0.4
    static let screenMarginX: CGFloat = 20
    static let screenMarginY: CGFloat = 72
}

// MARK: - Planet Slot

/// Pure index identifier (0–3); actual data comes from the ViewModel.
enum PlanetSlot: Int, CaseIterable, Identifiable {
    case slot0 = 0
    case slot1 = 1
    case slot2 = 2
    case slot3 = 3
    var id: Int { rawValue }
}

// MARK: - RadialMenuView

struct RadialMenuView: View {

    enum MenuState: Equatable {
        case idle
        case pressing
        case open
        case adjusting(PlanetSlot)
    }

    @Binding var showManualAdd: Bool

    @State private var dragStartTime: Date? = nil

    @Environment(PondaViewModel.self) private var viewModel

    @State private var menuState: MenuState = .idle
    @State private var fingerOffset: CGSize = .zero

    @State private var activePlanet: PlanetSlot? = nil
    @State private var proximityFactors: [Int: CGFloat] = [:]

    @State private var multiplier: Double = 1.0

    @State private var sliderStartY: CGFloat = 0
    @State private var sliderStartX: CGFloat = 0

    @State private var pressTask: Task<Void, Never>? = nil
    @State private var hoverTask: Task<Void, Never>? = nil

    // Ripple burst animation (FAB open)
    @State private var rippleStartTime: Date? = nil
    // Ripple burst animation (satellite lock)
    @State private var lockRippleStartTime: Date? = nil
    @State private var lockRippleOriginOffset: CGSize = .zero
    private let rippleDuration: Double = 0.8

    private let C = RadialMenuConstants.self

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            rippleScrim
            infoLabel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 32)
                .padding(.top, 80)
                .zIndex(1)
                .allowsHitTesting(false)
            menuCluster
                .padding(.bottom, C.screenMarginY)
                .padding(.trailing, C.screenMarginX)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sub-views

    private var scrimOpacity: Double {
        switch menuState {
        case .idle: 0
        case .pressing: 0.2
        default: C.scrimOpacity
        }
    }

    private var scrimHitTestable: Bool {
        menuState != .idle && menuState != .pressing
    }

    private func rippleElapsed(from timeline: TimelineViewDefaultContext) -> Float {
        // Suppress first ripple while lock ripple is active to avoid stacked distortion
        guard lockRippleStartTime == nil else { return -1 }
        guard let start = rippleStartTime else { return -1 }
        let t = timeline.date.timeIntervalSince(start)
        if t > rippleDuration {
            DispatchQueue.main.async { rippleStartTime = nil }
        }
        return Float(t)
    }

    private func lockRippleElapsed(from timeline: TimelineViewDefaultContext) -> Float {
        guard let start = lockRippleStartTime else { return -1 }
        let t = timeline.date.timeIntervalSince(start)
        if t > rippleDuration {
            DispatchQueue.main.async { lockRippleStartTime = nil }
        }
        return Float(t)
    }

    private var rippleScrim: some View {
        let anyRippleActive = rippleStartTime != nil || lockRippleStartTime != nil
        return TimelineView(.animation(paused: !anyRippleActive)) { timeline in
            let elapsed = rippleElapsed(from: timeline)
            let lockElapsed = lockRippleElapsed(from: timeline)

            scrimBackground(elapsed: elapsed, lockElapsed: lockElapsed)
        }
    }

    private func scrimBackground(elapsed: Float, lockElapsed: Float) -> some View {
        let marginX = C.screenMarginX
        let marginY = C.screenMarginY
        let fab = C.fabSize
        let dur = Float(rippleDuration)
        let lockOffset = lockRippleOriginOffset

        return Color.black
            .opacity(scrimOpacity)
            .ignoresSafeArea()
            .animation(C.menuSpring, value: menuState)
            .compositingGroup()
            .visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.rippleColorBurst(
                        .float2(
                            Float(proxy.size.width - marginX - fab / 2),
                            Float(proxy.size.height - marginY - fab / 2)
                        ),
                        .float(elapsed)
                    ),
                    maxSampleOffset: CGSize(width: 48, height: 48),
                    isEnabled: elapsed >= 0 && elapsed <= dur
                )
            }
            .visualEffect { content, proxy in
                content.layerEffect(
                    ShaderLibrary.rippleColorBurst(
                        .float2(
                            Float(proxy.size.width - marginX - fab / 2) + Float(lockOffset.width),
                            Float(proxy.size.height - marginY - fab / 2) + Float(lockOffset.height)
                        ),
                        .float(lockElapsed)
                    ),
                    maxSampleOffset: CGSize(width: 48, height: 48),
                    isEnabled: lockElapsed >= 0 && lockElapsed <= dur
                )
            }
            .contentShape(Rectangle())
            .onTapGesture { if menuState != .idle { closeMenu() } }
            .allowsHitTesting(scrimHitTestable)
    }

    @ViewBuilder
    private var infoLabel: some View {
        if menuState != .idle && menuState != .pressing {
            let displayPlanet: PlanetSlot? = {
                if case .adjusting(let p) = menuState { return p }
                return activePlanet
            }()

            if let planet = displayPlanet {
                let item = viewModel.getSlotData(for: planet.id)

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    if multiplier == 0.0 {
                        Text(String(localized: "common.cancel", defaultValue: "Cancel"))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .transition(.opacity.combined(with: .scale))
                    } else {
                        VStack(alignment: .leading) {
                            HStack(spacing: DS.Spacing.xs) {
                                Text(item.category.displayName)
                                    .font(.body)
                                    .foregroundStyle(.secondary)

                                if multiplier != 1.0 {
                                    Text("×\(String(format: "%.1f", multiplier))")
                                        .font(.system(.callout, design: .rounded, weight: .heavy))
                                        .foregroundStyle(DS.Colors.accentColor)
                                }
                            }

                            HStack(alignment: .lastTextBaseline, spacing: DS.Spacing.xs) {
                                Text(String(format: "%.0f", item.ml * multiplier))
                                    .contentTransition(.numericText())
                                    .font(.system(size: 56, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text(String(localized: "ml", defaultValue: "ml"))
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }

                            if case .adjusting(_) = menuState {
                                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                                    Divider()
                                        .background(Color.white)
                                        .padding(.vertical, DS.Spacing.s)
                                        .frame(width: 120)
                                    Text(String(localized: "radialMenu.adjust.slideVertical", defaultValue: "Slide up or down to adjust"))
                                    Text(String(localized: "radialMenu.adjust.slideHorizontalToCancel", defaultValue: "Slide left or right to cancel"))
                                    Text(String(localized: "radialMenu.adjust.releaseToConfirm", defaultValue: "Release to confirm"))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .foregroundStyle(.white)
                    }
                }
                .transition(.opacity)
                .animation(.easeOut(duration: 0.2), value: planet.id)
                .animation(C.scaleSpring, value: multiplier)
            }
        }
    }

    private var menuCluster: some View {
        ZStack {
            ForEach(PlanetSlot.allCases) { planet in
                let isDeployed = menuState == .open || menuState == .adjusting(planet)
                satelliteView(for: planet)
                    .offset(isDeployed
                        ? satelliteOffset(for: planet, proximity: proximityFactors[planet.id] ?? 0)
                        : .zero
                    )
                    .opacity(satelliteOpacity(for: planet))
                    .animation(C.menuSpring, value: menuState)
            }
            fabButton
        }
        .frame(width: C.fabSize, height: C.fabSize)
    }

    private func satelliteOpacity(for planet: PlanetSlot) -> Double {
        switch menuState {
        case .idle, .pressing: return 0
        case .open: return 1
        case .adjusting(let lockedPlanet): return planet == lockedPlanet ? 1.0 : 0.0
        }
    }

    private func satelliteView(for planet: PlanetSlot) -> some View {
        let proximity = proximityFactors[planet.id] ?? 0
        let isLocked = menuState == .adjusting(planet)
        let effectiveProximity = isLocked ? 1.0 : proximity
        let visualScale = lerp(1, C.satelliteActiveSize / C.satelliteNormalSize, t: effectiveProximity)
        let isCancelling = (isLocked && multiplier == 0.0)

        let item = viewModel.getSlotData(for: planet.id)

        return ZStack {
            satelliteBackground(isLocked: isLocked)

            Group {
                // Supports SF Symbol names or "char:X" for single-character icons
                if item.iconName.hasPrefix("char:") {
                    Text(String(item.iconName.dropFirst(5)))
                        .font(.system(size: lerp(18, 24, t: effectiveProximity), weight: .bold, design: .rounded))
                } else {
                    Image(systemName: item.iconName)
                        .font(.system(size: lerp(20, 26, t: effectiveProximity), weight: .medium))
                }
            }
            .foregroundStyle(isLocked ? Color.primary : Color.white)
        }
        .frame(width: C.satelliteNormalSize, height: C.satelliteNormalSize)
        .scaleEffect(isCancelling ? 0.9 : visualScale)
        .opacity(isCancelling ? 0 : 1)
        .animation(C.scaleSpring, value: isCancelling)
        .animation(C.scaleSpring, value: effectiveProximity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: item))
        .accessibilityHidden(menuState == .idle || menuState == .pressing || isCancelling)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func satelliteBackground(isLocked: Bool) -> some View {
        if #available(iOS 26.0, *), DebugSettings.shared.usesIOS26Behavior {
            Color.clear
                .glassEffect(.clear.tint(.secondary), in: .circle)
                .overlay {
                    Circle()
                        .fill(.white)
                        .opacity(isLocked ? 0.94 : 0)
                }
        } else {
            Circle()
                .fill(isLocked ? .white : .gray)
        }
    }

    private var fabButton: some View {
        Image(systemName: "plus")
            .font(.system(.title3, weight: .semibold))
            .glassCircle(.fab, size: C.fabSize)
            .scaleEffect(menuState != .idle && menuState != .pressing ? 0.1 : (menuState == .pressing ? 0.9 : 1.0))
            .opacity(menuState != .idle && menuState != .pressing ? 0.1 : 1.0)
            .animation(C.menuSpring, value: menuState)
            .gesture(safeDragGesture)
            .accessibilityLabel(String(localized: "radialMenu.quickAdd", defaultValue: "Quick add"))
            .accessibilityAddTraits(.isButton)
    }

    private func accessibilityLabel(for item: PondaItem) -> String {
        item.name.isEmpty ? item.category.displayName : item.name
    }

    // MARK: - Gesture (tap vs long-press vs drag)

    private var safeDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let loc = value.location
                let centeredOffset = CGSize(width: loc.x - C.fabSize / 2, height: loc.y - C.fabSize / 2)

                if menuState == .idle {
                    // 1. Touch down: record time, shrink FAB as press feedback
                    dragStartTime = Date()
                    withAnimation(.easeOut(duration: 0.15)) { menuState = .pressing }

                    // 2. Start long-press timer: fan out after threshold
                    pressTask = Task {
                        try? await Task.sleep(nanoseconds: UInt64(C.longPressDuration * 1_000_000_000))
                        if !Task.isCancelled {
                            rippleStartTime = Date()
                            withAnimation(C.menuSpring) { menuState = .open }
                            if DS.Haptics.isEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                        }
                    }
                }
                else if menuState == .open {
                    fingerOffset = centeredOffset
                    updateProximity(currentOffset: centeredOffset)
                }
                else if case .adjusting(_) = menuState {
                    let dragDistanceUp = sliderStartY - centeredOffset.height
                    let dragDistanceLeft = sliderStartX - centeredOffset.width

                    let step = Int(dragDistanceUp / 35)
                    var newMultiplier = max(0, 1.0 + Double(step) * 0.5)

                    // Horizontal drag beyond threshold → cancel
                    if dragDistanceLeft > 60 || dragDistanceLeft < -60 {
                        newMultiplier = 0.0
                    }

                    if newMultiplier != multiplier {
                        multiplier = newMultiplier
                        if DS.Haptics.isEnabled {
                            if multiplier == 0.0 {
                                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                            } else {
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                        }
                    }
                }
            }
            .onEnded { value in
                // A. Compute gesture metrics
                let duration = Date().timeIntervalSince(dragStartTime ?? Date())
                let distance = hypot(value.translation.width, value.translation.height)

                // B. Cancel timers
                pressTask?.cancel(); pressTask = nil
                hoverTask?.cancel(); hoverTask = nil

                // C. Determine intent

                // Branch 1: short tap (duration < 0.25s, distance < 10pt) → manual add sheet
                if duration < 0.25 && distance < 10 {
                    showManualAdd = true
                    if DS.Haptics.isEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                }
                // Branch 2: locked satellite → confirm or cancel
                else if case .adjusting(let planet) = menuState {
                    let item = viewModel.getSlotData(for: planet.id)
                    if multiplier > 0 {
                        viewModel.addEntry(item: item, multiplier: multiplier)
                        if DS.Haptics.isEnabled { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                    }
                } else if menuState == .open, let planet = activePlanet {
                    let item = viewModel.getSlotData(for: planet.id)
                    viewModel.addEntry(item: item, multiplier: 1.0)
                    if DS.Haptics.isEnabled { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                }

                // D. Reset all state
                closeMenu()
                dragStartTime = nil
            }
    }

    // MARK: - Actions

    private func closeMenu() {
        withAnimation(C.menuSpring) {
            menuState = .idle
            activePlanet = nil
            fingerOffset = .zero
            proximityFactors = [:]
            multiplier = 1.0
        }
    }

    private func updateProximity(currentOffset: CGSize) {
        var closestPlanet: PlanetSlot? = nil
        var closestDistance: CGFloat = .infinity

        for planet in PlanetSlot.allCases {
            let offset = satelliteOffset(for: planet, proximity: 0)
            let dist = hypot(currentOffset.width - offset.width, currentOffset.height - offset.height)
            if dist < closestDistance { closestDistance = dist; closestPlanet = planet }
        }

        var newFactors: [Int: CGFloat] = [:]
        for planet in PlanetSlot.allCases {
            if planet == closestPlanet && closestDistance < 90 {
                let easeOutFactor = sin(max(0, 1 - (closestDistance / 90)) * .pi / 2)
                newFactors[planet.id] = easeOutFactor
            } else {
                newFactors[planet.id] = 0.0
            }
        }
        proximityFactors = newFactors

        let newActive = closestDistance < C.magnetThreshold ? closestPlanet : nil

        if newActive != activePlanet {
            hoverTask?.cancel()
            hoverTask = nil

            withAnimation(C.scaleSpring) { activePlanet = newActive }

            if let active = newActive {
                if DS.Haptics.isEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }

                hoverTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if !Task.isCancelled {
                        self.sliderStartY = self.fingerOffset.height
                        self.sliderStartX = self.fingerOffset.width

                        // Kill first ripple so two don't overlap
                        self.rippleStartTime = nil
                        // Trigger lock ripple from the satellite's position
                        self.lockRippleOriginOffset = satelliteOffset(for: active, proximity: 1.0)
                        self.lockRippleStartTime = Date()

                        withAnimation(C.menuSpring) {
                            self.menuState = .adjusting(active)
                        }
                        if DS.Haptics.isEnabled { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
                    }
                }
            }
        }
    }

    // MARK: - Layout Math

    private func satelliteOffset(for planet: PlanetSlot, proximity: CGFloat) -> CGSize {
        let effectiveProximity: CGFloat
        if case .adjusting(let lockedPlanet) = menuState, lockedPlanet == planet {
            effectiveProximity = 1.0
        } else {
            effectiveProximity = proximity
        }

        let angleDeg = RadialMenuConstants.startAngle - Double(planet.rawValue) * RadialMenuConstants.stepAngle
        let rad: Double = angleDeg * .pi / 180.0
        let x = CGFloat(Foundation.cos(rad))
        let y = CGFloat(Foundation.sin(rad))

        let currentRadius = RadialMenuConstants.radius + (effectiveProximity * RadialMenuConstants.escapeDistance)
        return CGSize(width: currentRadius * x, height: currentRadius * y)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, t: CGFloat) -> CGFloat {
        return a + (b - a) * min(max(t, 0), 1)
    }
}
