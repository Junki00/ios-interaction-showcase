//
//  DesignSystem.swift
//  ponda
//
//  Centralized design tokens: colors, spacing, typography,
//  shadows, spring animations, and haptic-feedback policy.
//
//  Reference these tokens instead of hard-coding values in views.
//
//  Created by drx on 2026/03/12.
//

import SwiftUI

// MARK: - Namespace

/// Top-level design system namespace.
/// Access tokens via `DS.Colors`, `DS.Spacing`, etc.
enum DS {

    // MARK: - Colors

    enum Colors {
        static let accentColor = Color(hex: "#4F82BB")
        static let backgroundBase = Color(hex: "#F5F5F5")
    }

    // MARK: - Spacing (4pt base grid)

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 8
        static let s:   CGFloat = 12
        static let m:   CGFloat = 16
        static let l:   CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: - Typography
    // Only define display-scale fonts here; use system semantic styles
    // (.body, .caption, etc.) for everything else.

    enum Typography {
        static let megaSize: CGFloat = 44
        static let displayMega: Font = .system(size: megaSize, weight: .bold, design: .rounded)
    }

    // MARK: - Shadows
    // Dual-layer elevation inspired by Material Design:
    // ambient (soft, large radius) + key (directional, small radius).

    enum Shadow {
        /// Ambient — soft environmental shadow that conveys presence
        static let cardAmbient = ShadowStyle(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
        /// Key — directional contact shadow that conveys elevation
        static let cardKey     = ShadowStyle(color: .black.opacity(0.08), radius: 4, x: 0, y: 3)
        /// Lifted — exaggerated shadow used briefly during celebration animations
        static let cardLifted  = ShadowStyle(color: .black.opacity(0.3), radius: 40, x: 0, y: 20)
    }

    // MARK: - Animations
    // Categorized by perceived physical weight rather than by screen.
    // Tuning these values updates the feel across the entire app at once.

    enum Animation {

        // MARK: General-purpose tiers

        /// Light / crisp — small buttons, state toggles, quick feedback
        static let snappy = SwiftUI.Animation.spring(response: 0.25, dampingFraction: 0.7)

        /// Smooth / fluid — page transitions, list insertions, message appear/dismiss
        static let fluid = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.9)

        /// Heavy / physical — large panels, completion lift
        static let heavy = SwiftUI.Animation.spring(response: 0.45, dampingFraction: 0.75)

        // MARK: Scene-specific (hand-tuned)

        /// Card layer reveal — slow, gentle cascading disclosure
        static let cardReveal = SwiftUI.Animation.spring(response: 0.55, dampingFraction: 0.82)

        /// Radial menu deploy — medium speed, slightly bouncy fan-out
        static let menuPop = SwiftUI.Animation.spring(response: 0.38, dampingFraction: 0.78)
    }

    // MARK: - Haptics

    enum Haptics {
        private static let key = "settings.hapticsEnabled"

        static var isEnabled: Bool {
            get { !UserDefaults.standard.bool(forKey: key) }  // default true (key absent → false → !false = true)
            set { UserDefaults.standard.set(!newValue, forKey: key) }
        }
    }

    // Semantic mapping (imperative call-sites, not wrapped):
    //
    // ┌──────────────────────────────────┬──────────────────────────────────────────┐
    // │ Semantic context                 │ Haptic type                              │
    // ├──────────────────────────────────┼──────────────────────────────────────────┤
    // │ UI expand / navigation           │ .light impact                            │
    // │ Discrete selection change         │ UISelectionFeedbackGenerator             │
    // │ Playful visual accompaniment      │ .soft impact                             │
    // │ Data saved successfully           │ UINotificationFeedbackGenerator .success  │
    // │ Mode lock / major state change    │ .heavy impact                            │
    // │ Cancel / reject                   │ .rigid impact                            │
    // │ Milestone / one-time achievement  │ UINotificationFeedbackGenerator .success  │
    // │ Settings save (distinguish from   │ .medium impact                           │
    // │   "entry added")                  │                                          │
    // └──────────────────────────────────┴──────────────────────────────────────────┘
    //
    // Principles:
    // - Dense haptics during Radial Menu gesture flow are intentional (game-pad feel).
    // - Outside gesture flows, stay restrained — fire only on explicit user actions.
    // - The same semantic must use the same haptic across all entry points
    //   (e.g. "add entry" = .success everywhere).
    // - Provide a toggle to disable haptics (HIG: "Make haptics optional.").

}




// MARK: - Shadow Value Type

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View + Shadow helpers

extension View {
    func shadow(style s: ShadowStyle) -> some View {
        self.shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }

    /// Dual-layer card shadow (ambient + key).
    /// Pass `lifted: true` to switch to the exaggerated celebration shadow.
    func cardShadow(lifted: Bool = false) -> some View {
        self
            .shadow(style: lifted ? DS.Shadow.cardLifted : DS.Shadow.cardAmbient)
            .shadow(style: lifted ? ShadowStyle(color: .clear, radius: 0, x: 0, y: 0) : DS.Shadow.cardKey)
    }

    /// Prominent stage button shared across Gallery / MotionPainting / Welcome.
    /// On iOS 26+ uses Liquid Glass (`.glass` + `.controlSize(.extraLarge)`).
    /// On older systems falls back to a solid capsule with equivalent padding.
    ///
    /// Usage: `Button { } label: { ... }.stageButton()`
    /// For tinted variants: `.stageButton(tint: DS.Colors.accentColor)`
    @ViewBuilder
    func stageButton(tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *), DebugSettings.shared.usesIOS26Behavior {
            self
                .fontWeight(.semibold)
                .foregroundStyle(tint != nil ? Color.white : Color.primary)
                .buttonStyle(.glass(tint.map { .clear.tint($0) } ?? .clear))
                .controlSize(.extraLarge)
        } else {
            // Fallback: solid capsule button
            self
                .fontWeight(.semibold)
                .foregroundStyle(tint != nil ? Color.white : Color.primary)
                .padding(.horizontal, 32).padding(.vertical, 16)
                .background(tint ?? Color(hex: "#EAEAEA"), in: Capsule())
        }
    }

    // MARK: - Adaptive Symbol Effects

    /// Continuous attention animation that degrades gracefully across OS versions.
    /// iOS 18+: wiggle · iOS 17: pulse · iOS 16: opacity fade.
    @ViewBuilder
    func adaptiveWiggle(isActive: Bool) -> some View {
        if #available(iOS 18.0, *), DebugSettings.shared.usesIOS18Behavior {
            self.symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 1.0)), isActive: isActive)
        } else if #available(iOS 17.0, *), DebugSettings.shared.usesIOS17Behavior {
            self.symbolEffect(.pulse, isActive: isActive)
        } else {
            self.opacity(isActive ? 1.0 : 0.7)
        }
    }

    /// One-shot bounce on value change (close / confirm buttons).
    @ViewBuilder
    func adaptiveBounce<T: Equatable>(trigger: T) -> some View {
        if #available(iOS 17.0, *), DebugSettings.shared.usesIOS17Behavior {
            self.symbolEffect(.bounce, value: trigger)
        } else {
            self
        }
    }
}

extension DS {
    enum GlassCircleStyle {
        case fab
        case orbital
        case locked

        var tint: Color {
            switch self {
            case .fab:      return .primary
            case .orbital:  return .secondary
            case .locked:   return .white
            }
        }

        var foreground: Color {
            switch self {
            case .fab:      return .white
            case .orbital:  return .white
            case .locked:   return .primary
            }
        }

        var fallbackBackground: Color {
            switch self {
            case .fab:      return .primary
            case .orbital:  return .gray
            case .locked:   return .white
            }
        }

        var fallbackForeground: Color {
            switch self {
            case .fab:      return .white
            case .orbital:  return .white
            case .locked:   return .primary
            }
        }
    }
}


// MARK: - Circular Glass Button (FAB / orbital satellites)

extension View {
    /// Circular glass button with automatic iOS 26 Liquid Glass / solid fallback.
    @ViewBuilder
    func glassCircle(_ style: DS.GlassCircleStyle, size: CGFloat) -> some View {
        if #available(iOS 26.0, *), DebugSettings.shared.usesIOS26Behavior {
            self
                .foregroundStyle(style.foreground)
                .frame(width: size, height: size)
                .glassEffect(.clear.tint(style.tint), in: .circle)
        } else {
            // Fallback: solid circle
            self
                .foregroundStyle(style.fallbackForeground)
                .frame(width: size, height: size)
                .background {
                    Circle().fill(style.fallbackBackground)
                }
        }
    }
}
