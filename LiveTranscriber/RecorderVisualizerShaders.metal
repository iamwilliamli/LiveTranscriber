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

static float aspectCircleMask(float2 uv, float2 center, float aspect, float radius, float softness) {
    float2 point = uv - center;
    point.x *= aspect;
    return circleMask(point, radius, softness);
}

static float lineMask(float2 uv, float2 start, float2 end, float aspect, float width, float softness) {
    float2 point = float2(uv.x * aspect, uv.y);
    float2 lineStart = float2(start.x * aspect, start.y);
    float2 lineEnd = float2(end.x * aspect, end.y);
    float2 segment = lineEnd - lineStart;
    float position = clamp(dot(point - lineStart, segment) / max(dot(segment, segment), 0.0001), 0.0, 1.0);
    float distanceFromLine = length(point - (lineStart + segment * position));
    return 1.0 - smoothstep(width, width + softness, distanceFromLine);
}

static float rectWindowMask(float2 uv, float2 center, float2 size, float softness) {
    float2 distanceFromEdge = abs(uv - center) - size * 0.5;
    float outsideDistance = length(max(distanceFromEdge, 0.0));
    float insideDistance = min(max(distanceFromEdge.x, distanceFromEdge.y), 0.0);
    float signedDistance = outsideDistance + insideDistance;
    return 1.0 - smoothstep(0.0, softness, signedDistance);
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
    float tapePack = circleMask(point, 0.235, 0.014) * (1.0 - circleMask(point, 0.095, 0.010));
    float tapeGrooves = tapePack * (0.54 + 0.46 * sin(radius * 185.0 + angle * 0.90));
    float outer = ringMask(point, 0.276, 0.011, 0.006);
    float bevel = ringMask(point, 0.247, 0.018, 0.014);
    float inner = ringMask(point, 0.085, 0.014, 0.006);
    float hub = circleMask(point, 0.049, 0.008);
    float holes = smoothstep(0.60, 0.98, cos(angle * 6.0)) *
        smoothstep(0.055, 0.072, radius) *
        (1.0 - smoothstep(0.172, 0.205, radius));
    float spokes = smoothstep(0.92, 1.0, abs(cos(angle * 3.0))) *
        smoothstep(0.085, 0.12, radius) *
        (1.0 - smoothstep(0.245, 0.268, radius));
    float rotationalGlint = smoothstep(0.965, 1.0, cos(angle - 0.75)) *
        smoothstep(0.115, 0.150, radius) *
        (1.0 - smoothstep(0.255, 0.285, radius));
    float glow = circleMask(point, 0.34 + level * 0.025, 0.08) * (0.12 + active * 0.18);

    return clamp(
        max(max(max(outer, inner), hub), max(max(holes * 0.70, spokes * 0.46), bevel * 0.36)) +
        tapeGrooves * 0.18 +
        rotationalGlint * 0.50 +
        glow,
        0.0,
        1.0
    );
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
    float vignette = smoothstep(0.98, 0.16, distance(uv, float2(0.5, 0.48)));
    float edgeFalloff = smoothstep(0.010, 0.120, uv.x) *
        smoothstep(0.990, 0.880, uv.x) *
        smoothstep(0.010, 0.150, uv.y) *
        smoothstep(0.990, 0.850, uv.y);

    float3 base = mix(float3(0.045, 0.047, 0.050), float3(0.095, 0.038, 0.030), 0.42);
    float3 warmPanel = base + uniforms.tint.rgb * (0.045 + active * 0.045);
    float3 color = warmPanel * (0.58 + vignette * 0.46);
    color *= 0.72 + edgeFalloff * 0.34;

    float window = rectWindowMask(uv, float2(0.5, 0.445), float2(0.700, 0.390), 0.045);
    color = mix(color, float3(0.018, 0.019, 0.021), window * 0.36);
    color += float3(0.95, 0.62, 0.42) *
        lineMask(uv, float2(0.175, 0.250), float2(0.825, 0.250), aspect, 0.0022, 0.008) *
        window * 0.055;

    float reflection = smoothstep(0.34, 0.0, abs(uv.y - 0.145)) *
        smoothstep(0.0, 0.42, uv.x) *
        (1.0 - smoothstep(0.55, 1.0, uv.x));
    color += float3(1.0, 0.82, 0.68) * reflection * 0.055;

    float glassSweep = lineMask(uv, float2(0.175, 0.215), float2(0.820, 0.615), aspect, 0.006, 0.055) * window;
    color += float3(1.0, 0.82, 0.64) * glassSweep * 0.058;

    float tapeBand = lineMask(uv, float2(0.190, 0.470), float2(0.810, 0.470), aspect, 0.010, 0.006);
    color = mix(color, float3(0.210, 0.078, 0.052), tapeBand * window * 0.76);

    float leftCapstan = aspectCircleMask(uv, float2(0.236, 0.588), aspect, 0.037, 0.008);
    float rightCapstan = aspectCircleMask(uv, float2(0.764, 0.588), aspect, 0.037, 0.008);
    float capstanRing = max(
        ringMask(float2((uv.x - 0.236) * aspect, uv.y - 0.588), 0.036, 0.006, 0.004),
        ringMask(float2((uv.x - 0.764) * aspect, uv.y - 0.588), 0.036, 0.006, 0.004)
    );
    color = mix(color, float3(0.090, 0.094, 0.100), max(leftCapstan, rightCapstan) * window * 0.62);
    color = mix(color, float3(0.40, 0.42, 0.43), capstanRing * window * 0.48);

    float leftReel = tapeReel(uv, float2(0.315, 0.43), aspect, time, level, active);
    float rightReel = tapeReel(uv, float2(0.685, 0.43), aspect, -time * 0.94, level, active);
    float leftReelShadow = aspectCircleMask(uv + float2(-0.006, -0.014), float2(0.315, 0.43), aspect, 0.312, 0.040);
    float rightReelShadow = aspectCircleMask(uv + float2(-0.006, -0.014), float2(0.685, 0.43), aspect, 0.312, 0.040);
    color *= 1.0 - max(leftReelShadow, rightReelShadow) * window * 0.135;
    float reelMask = clamp(leftReel + rightReel, 0.0, 1.0);
    float3 reelColor = mix(float3(0.130, 0.134, 0.142), uniforms.tint.rgb, 0.30 + active * 0.20);
    color = mix(color, reelColor, reelMask * 0.72);
    color += float3(0.95, 0.40, 0.28) * reelMask * level * active * 0.045;

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

    float screwTopLeft = aspectCircleMask(uv, float2(0.070, 0.115), aspect, 0.018, 0.006);
    float screwTopRight = aspectCircleMask(uv, float2(0.930, 0.115), aspect, 0.018, 0.006);
    float screwBottomLeft = aspectCircleMask(uv, float2(0.070, 0.895), aspect, 0.018, 0.006);
    float screwBottomRight = aspectCircleMask(uv, float2(0.930, 0.895), aspect, 0.018, 0.006);
    float screws = max(max(screwTopLeft, screwTopRight), max(screwBottomLeft, screwBottomRight));
    color = mix(color, float3(0.030, 0.032, 0.034), screws * 0.52);

    float screwSlots = max(
        max(
            lineMask(uv, float2(0.057, 0.115), float2(0.083, 0.115), aspect, 0.0018, 0.003),
            lineMask(uv, float2(0.917, 0.115), float2(0.943, 0.115), aspect, 0.0018, 0.003)
        ),
        max(
            lineMask(uv, float2(0.057, 0.895), float2(0.083, 0.895), aspect, 0.0018, 0.003),
            lineMask(uv, float2(0.917, 0.895), float2(0.943, 0.895), aspect, 0.0018, 0.003)
        )
    );
    color += float3(0.35, 0.34, 0.33) * screwSlots * 0.35;

    float scanline = 0.5 + 0.5 * sin(uv.y * uniforms.size.y * 0.62);
    float brushedMetal = 0.5 + 0.5 * sin((uv.x + uv.y * 0.06) * uniforms.size.x * 0.42);
    color -= scanline * 0.008;
    color += brushedMetal * 0.010;
    color += (hash11(uv.x * uniforms.size.x + uv.y * uniforms.size.y * 17.0 + time) - 0.5) * 0.016;

    return float4(color, 1.0);
}
