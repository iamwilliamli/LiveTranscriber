#include <metal_stdlib>
using namespace metal;

struct RecorderVisualizerUniforms {
    float time;
    float level;
    float active;
    uint historyCount;
    float2 size;
    float4 tint;
};

struct RecorderVisualizerVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex RecorderVisualizerVertexOut recorderVisualizerVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0)
    };

    constexpr float2 uvs[3] = {
        float2(0.0, 1.0),
        float2(2.0, 1.0),
        float2(0.0, -1.0)
    };

    RecorderVisualizerVertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

static float hash11(float value) {
    return fract(sin(value * 127.1) * 43758.5453);
}

static float circleMask(float2 point, float radius, float softness) {
    return 1.0 - smoothstep(radius, radius + softness, length(point));
}

static float ringMask(float2 point, float radius, float width, float softness) {
    float distanceFromRing = abs(length(point) - radius);
    return 1.0 - smoothstep(width, width + softness, distanceFromRing);
}

static float sampleHistory(float normalizedX, constant float *history, uint count) {
    if (count == 0) {
        return 0.0;
    }

    float scaledIndex = clamp(normalizedX, 0.0, 1.0) * float(count - 1);
    uint leftIndex = uint(floor(scaledIndex));
    uint rightIndex = min(leftIndex + 1, count - 1);
    return mix(history[leftIndex], history[rightIndex], fract(scaledIndex));
}

static float tapeReel(float2 uv, float2 center, float aspect, float time, float level, float active) {
    float2 point = uv - center;
    point.x *= aspect;

    float radius = length(point);
    float angle = atan2(point.y, point.x) + time * mix(0.18, 2.25, active);
    float outer = ringMask(point, 0.265, 0.010, 0.006);
    float inner = ringMask(point, 0.082, 0.012, 0.006);
    float hub = circleMask(point, 0.045, 0.008);
    float holes = smoothstep(0.60, 0.98, cos(angle * 6.0)) *
        smoothstep(0.055, 0.072, radius) *
        (1.0 - smoothstep(0.172, 0.205, radius));
    float spokes = smoothstep(0.92, 1.0, abs(cos(angle * 3.0))) *
        smoothstep(0.085, 0.12, radius) *
        (1.0 - smoothstep(0.245, 0.268, radius));
    float glow = circleMask(point, 0.34 + level * 0.025, 0.08) * (0.14 + active * 0.22);

    return max(max(max(outer, inner), hub), max(holes * 0.72, spokes * 0.42)) + glow;
}

fragment float4 recorderVisualizerFragment(
    RecorderVisualizerVertexOut in [[stage_in]],
    constant RecorderVisualizerUniforms &uniforms [[buffer(0)]],
    constant float *levelHistory [[buffer(1)]]
) {
    float2 uv = clamp(in.uv, 0.0, 1.0);
    float aspect = max(uniforms.size.x / max(uniforms.size.y, 1.0), 1.0);
    float active = uniforms.active;
    float level = clamp(uniforms.level, 0.0, 1.0);
    float time = uniforms.time;
    float vignette = smoothstep(0.96, 0.18, distance(uv, float2(0.5, 0.48)));

    float3 base = mix(float3(0.045, 0.047, 0.050), float3(0.095, 0.038, 0.030), 0.42);
    float3 warmPanel = base + uniforms.tint.rgb * (0.045 + active * 0.045);
    float3 color = warmPanel * (0.72 + vignette * 0.42);

    float reflection = smoothstep(0.34, 0.0, abs(uv.y - 0.16)) *
        smoothstep(0.0, 0.42, uv.x) *
        (1.0 - smoothstep(0.55, 1.0, uv.x));
    color += float3(1.0, 0.82, 0.68) * reflection * 0.055;

    float tapeBand = smoothstep(0.010, 0.0, abs(uv.y - 0.47)) *
        smoothstep(0.14, 0.20, uv.x) *
        (1.0 - smoothstep(0.80, 0.86, uv.x));
    color = mix(color, float3(0.23, 0.095, 0.070), tapeBand * 0.72);

    float leftReel = tapeReel(uv, float2(0.315, 0.43), aspect, time, level, active);
    float rightReel = tapeReel(uv, float2(0.685, 0.43), aspect, -time * 0.94, level, active);
    float reelMask = clamp(leftReel + rightReel, 0.0, 1.0);
    float3 reelColor = mix(float3(0.18, 0.18, 0.19), uniforms.tint.rgb, 0.34 + active * 0.22);
    color = mix(color, reelColor, reelMask * 0.72);

    float waveBase = 0.785;
    float historyLevel = sampleHistory(uv.x, levelHistory, uniforms.historyCount);
    float previousLevel = sampleHistory(max(uv.x - 0.010, 0.0), levelHistory, uniforms.historyCount);
    float nextLevel = sampleHistory(min(uv.x + 0.010, 1.0), levelHistory, uniforms.historyCount);
    float localPeak = max(historyLevel, max(previousLevel, nextLevel));
    float traceY = waveBase - localPeak * 0.320;
    float waveLine = 1.0 - smoothstep(0.004, 0.021, abs(uv.y - traceY));
    float waveGlow = 1.0 - smoothstep(0.010, 0.092, abs(uv.y - traceY));
    float timelineFloor = smoothstep(waveBase + 0.015, waveBase - 0.010, uv.y) *
        smoothstep(waveBase - 0.385, waveBase - 0.250, uv.y);
    color += uniforms.tint.rgb * timelineFloor * (0.024 + active * 0.032);
    color += uniforms.tint.rgb * waveGlow * (0.062 + active * 0.074);
    color = mix(color, float3(1.0, 0.34, 0.22), waveLine * (0.46 + active * 0.50));

    float scanline = 0.5 + 0.5 * sin(uv.y * uniforms.size.y * 0.62);
    color -= scanline * 0.010;
    color += (hash11(uv.x * uniforms.size.x + uv.y * uniforms.size.y * 17.0 + time) - 0.5) * 0.018;

    return float4(color, 1.0);
}
