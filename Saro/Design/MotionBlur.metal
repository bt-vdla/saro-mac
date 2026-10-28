#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// One axis of the web's feGaussianBlur (lib/motionBlur.ts): an x pass then a y pass make its separable stdDeviation(x, y).
// Taps sit about half a point apart over ±3σ, so text smears instead of ghosting.
[[ stitchable ]] half4 motionBlur(float2 position, SwiftUI::Layer layer, float2 axis, float sigma) {
    float reach = 3.0 * sigma;
    int n = clamp(int(ceil(reach * 2.0)), 1, 64);
    half4 sum = 0.0h;
    float total = 0.0;
    for (int i = -n; i <= n; i++) {
        float d = reach * float(i) / float(n);
        float w = exp(-0.5 * d * d / (sigma * sigma));
        sum += layer.sample(position + axis * d) * half(w);
        total += w;
    }
    return sum / half(total);
}
