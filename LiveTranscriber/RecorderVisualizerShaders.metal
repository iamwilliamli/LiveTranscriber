#include <metal_stdlib>
using namespace metal;

struct RecorderVisualizerUniforms {
    float time;
    float level;
    float active;
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
    constant RecorderVisualizerUniforms &uniforms [[buffer(0)]]
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

    float waveBase = 0.735;
    float wave = sin(uv.x * 31.0 + time * 3.0) * 0.018;
    wave += sin(uv.x * 69.0 - time * 2.1) * 0.010;
    wave += sin(uv.x * 107.0 + time * 1.35) * 0.006;
    wave *= (0.20 + active * (0.52 + level * 1.55));
    float waveLine = 1.0 - smoothstep(0.004, 0.018, abs(uv.y - (waveBase + wave)));
    float waveGlow = 1.0 - smoothstep(0.008, 0.070, abs(uv.y - (waveBase + wave)));
    color += uniforms.tint.rgb * waveGlow * (0.055 + active * 0.070);
    color = mix(color, float3(1.0, 0.34, 0.22), waveLine * (0.40 + active * 0.50));

    float columns = 34.0;
    float column = floor(uv.x * columns);
    float localX = fract(uv.x * columns);
    float randomHeight = hash11(column + 9.0);
    float pulse = 0.5 + 0.5 * sin(time * 4.2 + column * 0.63);
    float barHeight = 0.022 + active * (0.030 + level * 0.135 + randomHeight * pulse * 0.030);
    float barX = step(0.24, localX) * step(localX, 0.76) * step(0.075, uv.x) * step(uv.x, 0.925);
    float barY = step(abs(uv.y - 0.885), barHeight);
    float bars = barX * barY;
    color = mix(color, mix(float3(0.95, 0.22, 0.12), float3(1.0, 0.74, 0.32), level), bars * 0.82);

    float scanline = 0.5 + 0.5 * sin(uv.y * uniforms.size.y * 0.62);
    color -= scanline * 0.010;
    color += (hash11(uv.x * uniforms.size.x + uv.y * uniforms.size.y * 17.0 + time) - 0.5) * 0.018;

    return float4(color, 1.0);
}
