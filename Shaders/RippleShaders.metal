//
//  RippleShaders.metal
//  ponda
//
//  Metal shaders for ripple distortion effects used with SwiftUI's
//  `.visualEffect` / `.layerEffect` modifiers.
//
//  The numbered "step" functions document the iterative design process
//  from a bare-bones single-ring ripple to the final production shader
//  (rippleColorBurst) featuring chromatic dispersion and accent-color glow.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;


// ============================================================================
// MARK: - Learning progression (distortionEffect shaders)
// ============================================================================
//
// Each step builds on the previous one. The numbered names are kept
// intentionally so you can wire them up one-by-one and see the difference.


/// Step 2 — Basic expanding ring distortion.
/// A single ring expands outward from `touchPos`. Pixels inside the ring
/// are displaced radially, creating a visible "bump" in the image.
[[ stitchable ]] float2 rippleStep2(
    float2 position,
    float2 touchPos,
    float elapsed
) {
    float currentRadius = elapsed * 500.0;
    float distortionIntensity = max(0.0, (3.0 - elapsed) / 3.0);
    float dist = distance(position, touchPos);
    float diff = dist - currentRadius;

    if (abs(diff) < 30.0) {
        float2 direction = normalize(position - touchPos);
        float offsetAmount = distortionIntensity * 20.0;
        return position - direction * offsetAmount;
    }
    return position;
}


/// Step 3 — Smooth cosine envelope.
/// Replaces the hard 30px band with a cos() falloff so the ring edge
/// blends smoothly into undistorted pixels.
[[ stitchable ]] float2 rippleStep3(
    float2 position,
    float2 touchPos,
    float elapsed
) {
    float currentRadius = elapsed * 500.0;
    float distortionIntensity = max(0.0, (3.0 - elapsed) / 3.0);
    float dist = distance(position, touchPos);
    float diff = dist - currentRadius;

    if (abs(diff) < 30.0) {
        float angle = (diff / 30.0) * M_PI_F;
        float falloff = (1.0 + cos(angle)) * 0.5;
        float offsetAmount = distortionIntensity * 30.0 * falloff;
        float2 direction = normalize(position - touchPos);
        return position - direction * offsetAmount;
    }
    return position;
}


/// Step 4 — Distance-based decay.
/// Energy decreases as the ring travels farther from the origin,
/// mimicking real water ripples that weaken with distance.
[[ stitchable ]] float2 rippleStep4(
    float2 position,
    float2 touchPos,
    float elapsed
) {
    float currentRadius = elapsed * 400.0;
    float distortionIntensity = max(0.0, (4.0 - elapsed) / 4.0);
    float dist = distance(position, touchPos);
    float distanceDecay = max(0.0, (500.0 - dist)) / 500.0;
    float diff = dist - currentRadius;

    if (abs(diff) < 40.0) {
        float angle = (diff / 40.0) * M_PI_F;
        float falloff = (1.0 + cos(angle)) * 0.5;
        float offsetAmount = distortionIntensity * 40.0 * falloff * distanceDecay;
        float2 direction = normalize(position - touchPos);
        return position - direction * offsetAmount;
    }
    return position;
}


/// Step 5 — Multiple concentric rings.
/// Instead of one ring, uses sin() to produce several wavefronts wrapped
/// in a wide cosine envelope. The result looks like a pebble-in-water effect.
[[ stitchable ]] float2 rippleStep5(
    float2 position,
    float2 touchPos,
    float elapsed
) {
    float currentRadius = elapsed * 400.0;
    float distortionIntensity = max(0.0, (4.0 - elapsed) / 4.0);
    float dist = distance(position, touchPos);
    float distanceDecay = max(0.0, (500.0 - dist)) / 500.0;
    float diff = dist - currentRadius;

    if (abs(diff) < 150.0) {
        float wave = sin(diff * 0.08);
        float envelope = (1.0 + cos((diff / 150.0) * M_PI_F)) * 0.5;
        float offsetAmount = 10.0 * distanceDecay * distortionIntensity * wave * envelope;
        float2 direction = normalize(position - touchPos);
        return position - direction * offsetAmount;
    }
    return position;
}


/// Step 6 — Production-safe single ring.
/// Adds a near-origin guard (dist < 0.1) to prevent normalize(zero) NaN,
/// and an elapsed bounds check to skip work outside the animation window.
[[ stitchable ]] float2 rippleStep6(
    float2 position,
    float2 touchPos,
    float elapsed
) {
    float dist = distance(position, touchPos);
    if (dist < 0.1) { return position; }

    float currentRadius = elapsed * 400.0;
    float distortionIntensity = max(0.0, (4.0 - elapsed) / 4.0);
    float distanceDecay = max(0.0, (500.0 - dist)) / 500.0;
    float diff = dist - currentRadius;

    if (elapsed < 0.0 || elapsed > 4.0) { return position; }

    if (abs(diff) < 40.0) {
        float angle = (diff / 40.0) * M_PI_F;
        float falloff = (1.0 + cos(angle)) * 0.5;
        float offsetAmount = distortionIntensity * 40.0 * falloff * distanceDecay;
        float2 direction = (position - touchPos) / dist;
        return position - direction * offsetAmount;
    }
    return position;
}


// ============================================================================
// MARK: - Production shader (layerEffect)
// ============================================================================

/// Chromatic-dispersion ripple burst with accent-color glow.
///
/// Used as a `layerEffect` in SwiftUI via `ShaderLibrary.rippleColorBurst(...)`.
/// Fires once on menu open and again on satellite lock, producing a single
/// expanding ring (~0.8 s) with:
///   - spring ease-out expansion (1 - e^{-3.5t})
///   - per-channel radial sampling offset → chromatic aberration
///   - angle-modulated accent highlight (#4F82BB)
///   - near-field suppression to avoid over-bright origin
///
/// Parameters:
///   origin  — screen-space center of the burst (e.g. FAB position)
///   elapsed — seconds since trigger (negative = inactive)
[[ stitchable ]] half4 rippleColorBurst(
    float2 position,
    SwiftUI::Layer layer,
    float2 origin,
    float elapsed
) {
    float dist = distance(position, origin);

    float duration = 0.8;
    float maxReach = 600.0;

    // Spring ease-out expansion
    float progress = 1.0 - exp(-3.5 * elapsed);
    float currentRadius = maxReach * progress;

    // Time fade (linear) and distance fade (sqrt for softer rolloff)
    float timeFade = max(0.0, (duration - elapsed) / duration);
    float distFade = max(0.0, (maxReach - dist) / maxReach);
    distFade = sqrt(distFade);

    float diff = dist - currentRadius;
    float ringWidth = 100.0;

    if (abs(diff) < ringWidth && dist > 0.1) {
        // Single-ring cosine envelope
        float envelope = (1.0 + cos((diff / ringWidth) * M_PI_F)) * 0.5;
        // Suppress near-origin brightness
        float nearFade = smoothstep(0.0, 80.0, dist);
        float strength = timeFade * distFade * envelope * nearFade;

        // Geometric distortion
        float2 dir = (position - origin) / dist;
        float distort = strength * 10.0;
        float2 baseOffset = dir * distort;

        // Chromatic dispersion: offset R/G/B channels along the radial axis
        float dispersion = strength * 14.0;
        half4 innerSample  = layer.sample(position - baseOffset + dir * dispersion);
        half4 centerSample = layer.sample(position - baseOffset);
        half4 outerSample  = layer.sample(position - baseOffset - dir * dispersion);

        // Recombine: R from inner, G from center, B from outer
        half4 result = half4(innerSample.r, centerSample.g, outerSample.b, centerSample.a);

        // Accent-color glow (#4F82BB ≈ 0.31, 0.51, 0.73), angle-modulated
        float glow = strength * 0.16;
        float angle = atan2(position.y - origin.y, position.x - origin.x);
        half3 accentHue = half3(
            (half)(0.31 + 0.06 * sin(angle * 3.0)),
            (half)(0.51 + 0.08 * sin(angle * 3.0 + 1.0)),
            (half)(0.73 + 0.10 * sin(angle * 3.0 + 2.0))
        );
        result.rgb += accentHue * (half)glow;

        return result;
    }

    return layer.sample(position);
}
