#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The lens's velocity smear (lensScene.ts): four taps back along the tiles' motion, up to 6 pt, so a fast pinch or flick
// reads as movement rather than strobing. Off at rest and under Reduce Motion (the view stops applying it).
[[ stitchable ]] half4 lensSmear(float2 position, SwiftUI::Layer layer, float2 velocity) {
    half4 sum = 0.0h;
    for (int i = 0; i < 4; i++) {
        sum += layer.sample(position - velocity * (float(i) / 3.0));
    }
    return sum * 0.25h;
}
