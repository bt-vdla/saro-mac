#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The web ground's fragment shader (saro/frontend/components/ground/LitGround.tsx), line for line: a pool of light
// (stretched along the horizon when the light is low), a glow on the horizon under it, each also casting its hue on the
// ground, haze, still star dust at night, a faint vignette and still grain. `position` is in points from the top left.

constant float3 LUMA = float3(0.2126, 0.7152, 0.0722);

static float hash(float2 q) { return fract(precise::sin(dot(q, float2(12.9898, 78.233))) * 43758.5453); }

static float3 toSrgb(float3 c) { return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, c * 12.92, c <= 0.0031308); }

static float3 tinted(float3 col, float3 hue, float strength) {
    float lum = dot(col, LUMA);
    return mix(col, min(hue * (lum / max(dot(hue, LUMA), 1e-4)), float3(1.0)), strength);
}

[[ stitchable ]] half4 litGround(float2 position, half4 color, float2 size, float dpr, float2 sun, float spread,
                                 float stretch, float3 ground, float falloff, float3 light, float power, float3 accent,
                                 float accentPower, float cast, float3 hazeColor, float3 hazeLift, float hazeCast,
                                 float stars, float3 grainK, float starPeak, float grainFloor) {
    float2 uv = position / size;
    float2 aspect = float2(size.x / size.y, 1.0);
    // Device pixel centres, as gl_FragCoord.
    float2 p = floor(position * dpr) + 0.5;

    float2 q = (uv - sun) * aspect;
    float d = length(float2(q.x / stretch, q.y)) / spread;
    float pool = exp(-d * d * 2.4);
    float2 b = float2((uv.x - sun.x) * aspect.x / 0.9, (1.0 - uv.y) / 0.3);
    float band = exp(-dot(b, b));
    float3 col = mix(ground, ground * falloff, smoothstep(0.0, 1.5, d));
    col += light * power * pool + accent * accentPower * band + hazeLift;
    col = tinted(col, light, cast * pool);
    col = tinted(col, accent, cast * band);
    col = tinted(col, hazeColor, hazeCast);
    float2 cell = floor(p / (1.25 * dpr));
    col += float3(0.85, 0.9, 1.0) * (stars * starPeak) * step(0.9975, hash(cell + 7.0)) * (0.4 + 0.6 * hash(cell + 3.0));

    col *= mix(0.9, 1.0, 1.0 - smoothstep(0.3, 1.3, length((uv - 0.5) * aspect * 0.9)));
    float soft = 0.25 * (hash(p) + hash(p + float2(1.0, 0.0)) + hash(p + float2(0.0, 1.0)) + hash(p + float2(1.0, 1.0)));
    float grain = mix(hash(p), soft, grainK.y) - 0.5;
    float3 lit = clamp(col, 0.0, 1.0);
    float3 s = toSrgb(lit);
    float3 night = s + grain * grainK.x;
    float w = smoothstep(0.3, 0.6, dot(s, LUMA));
    if (w == 0.0) return half4(half3(night), 1.0h);
    // Day: still cells of whole device px, each minus its 4 neighbours' mean, dark-leaning like a print; +0.081 keeps
    // the mean on the ground.
    float2 c = floor(p / max(1.0, floor(1.25 * dpr + 0.5))) + 0.5;
    float n = hash(c) - 0.25 * (hash(c + float2(1.0, 0.0)) + hash(c - float2(1.0, 0.0)) + hash(c + float2(0.0, 1.0)) + hash(c - float2(0.0, 1.0)));
    float k = grainK.z * 1.95 * ((n < 0.0 ? n : 0.4 * n) + 0.081);
    float mx = max(max(s.r, s.g), max(s.b, 1e-3));
    // A speck never darkens the pixel below where ink-3 keeps AA, unless the night line's darkest speck already went deeper.
    k = max(k, min(-0.5 * grainK.x / mx, pow(grainFloor / dot(lit, LUMA), 1.0 / 2.4) - 1.0));
    // The bright half eases into the headroom below white instead of pinning at 255.
    float room = max(1.0 / mx - 1.0, 1e-4);
    float3 day = s * (1.0 + (k > 0.0 ? room * tanh(min(k / room, 8.0)) : k));
    return half4(half3(mix(night, day, w)), 1.0h);
}
