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

static float sampleHistory(float normalizedX, constant float *history, uint count) {
    if (count == 0) {
        return 0.0;
    }

    float scaledIndex = clamp(normalizedX, 0.0, 1.0) * float(count - 1);
    uint leftIndex = uint(floor(scaledIndex));
    uint rightIndex = min(leftIndex + 1, count - 1);
    return mix(history[leftIndex], history[rightIndex], fract(scaledIndex));
}

static float cleanLine(float y, float targetY, float width, float softness) {
    return 1.0 - smoothstep(width, width + softness, abs(y - targetY));
}

fragment float4 recorderVisualizerFragment(
    RecorderVisualizerVertexOut in [[stage_in]],
    constant RecorderVisualizerUniforms &uniforms [[buffer(0)]],
    constant float *levelHistory [[buffer(1)]]
) {
    float2 uv = clamp(in.uv, 0.0, 1.0);
    float active = uniforms.active;
    float level = clamp(uniforms.level, 0.0, 1.0);
    float3 accent = uniforms.tint.rgb;

    float edgeFalloff = smoothstep(0.0, 0.14, uv.x) *
        smoothstep(1.0, 0.86, uv.x) *
        smoothstep(0.0, 0.16, uv.y) *
        smoothstep(1.0, 0.82, uv.y);

    float3 topColor = float3(0.033, 0.036, 0.043);
    float3 bottomColor = float3(0.018, 0.020, 0.025);
    float3 color = mix(topColor, bottomColor, smoothstep(0.0, 1.0, uv.y));
    color += accent * (0.020 + active * 0.030) * smoothstep(0.85, 0.10, distance(uv, float2(0.50, 0.62)));
    color *= 0.82 + edgeFalloff * 0.18;

    float glassLine = cleanLine(uv.y, 0.155, 0.000, 0.120) *
        smoothstep(0.05, 0.36, uv.x) *
        smoothstep(0.72, 0.44, uv.x);
    color += float3(1.0, 0.78, 0.62) * glassLine * 0.028;

    float historyLevel = sampleHistory(uv.x, levelHistory, uniforms.historyCount);
    float previousLevel = sampleHistory(max(uv.x - 0.012, 0.0), levelHistory, uniforms.historyCount);
    float nextLevel = sampleHistory(min(uv.x + 0.012, 1.0), levelHistory, uniforms.historyCount);
    float envelope = pow(clamp(max(historyLevel, max(previousLevel, nextLevel)), 0.0, 1.0), 0.80);

    float centerY = 0.620;
    float amplitude = envelope * 0.300;
    float upperY = centerY - amplitude;
    float lowerY = centerY + amplitude * 0.72;
    float centerLine = cleanLine(uv.y, centerY, 0.001, 0.026);
    float upperLine = cleanLine(uv.y, upperY, 0.004, 0.040);
    float lowerLine = cleanLine(uv.y, lowerY, 0.003, 0.032);
    float fill = smoothstep(upperY - 0.018, upperY + 0.006, uv.y) *
        smoothstep(lowerY + 0.018, lowerY - 0.006, uv.y);

    float fade = smoothstep(0.04, 0.14, uv.x) * smoothstep(0.98, 0.84, uv.x);
    color += accent * fill * fade * (0.020 + active * 0.036);
    color += accent * upperLine * fade * (0.190 + active * 0.210);
    color += accent * lowerLine * fade * (0.070 + active * 0.075);
    color += accent * centerLine * fade * 0.032;
    color += float3(1.0, 0.42, 0.28) * upperLine * fade * level * active * 0.085;

    float latest = smoothstep(0.90, 0.965, uv.x) * smoothstep(1.0, 0.970, uv.x);
    color += accent * latest * level * active * 0.042;

    return float4(color, 1.0);
}
