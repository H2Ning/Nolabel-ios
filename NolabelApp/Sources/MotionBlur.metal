#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

/// Horizontal motion blur whose radius grows with the distance from the
/// vertical rotation axis, approximating the linear speed of a rotating body.
[[ stitchable ]] half4 motionBlur(float2 position, SwiftUI::Layer layer, float2 size, float amount) {
    float centerX = size.x * 0.5;
    float normalized = abs(position.x - centerX) / max(centerX, 1.0);
    float radius = amount * pow(normalized, 1.35);

    if (radius < 0.5) {
        return layer.sample(position);
    }

    const int sampleCount = 9;
    half4 sum = half4(0.0);
    for (int i = 0; i < sampleCount; i++) {
        float t = (float(i) / float(sampleCount - 1)) * 2.0 - 1.0;
        sum += layer.sample(position + float2(t * radius, 0.0));
    }
    return sum / half(sampleCount);
}
