#include <metal_stdlib>
using namespace metal;

struct RecorderVisualizerUniforms {
    float time;
    float level;
    float active;
    uint historyCount;
    float2 style;
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
    float lightMode = clamp(uniforms.style.x, 0.0, 1.0);
    float3 accent = uniforms.tint.rgb;
    float3 color = mix(float3(0.0), float3(1.0), lightMode);

    float historyLevel = sampleHistory(uv.x, levelHistory, uniforms.historyCount);
    float previousLevel = sampleHistory(max(uv.x - 0.012, 0.0), levelHistory, uniforms.historyCount);
    float nextLevel = sampleHistory(min(uv.x + 0.012, 1.0), levelHistory, uniforms.historyCount);
    float envelope = pow(clamp(max(historyLevel, max(previousLevel, nextLevel)), 0.0, 1.0), 0.80);

    float waveBaseY = 0.760;
    float waveY = waveBaseY - envelope * 0.420;
    float line = cleanLine(uv.y, waveY, 0.004, 0.038);
    float fade = smoothstep(0.04, 0.12, uv.x) * smoothstep(0.99, 0.88, uv.x);
    float strength = (0.78 + active * 0.16 + level * active * 0.06) * fade;
    float3 lineColor = mix(accent, accent * 0.90, lightMode);
    color = mix(color, lineColor, line * strength);

    return float4(color, 1.0);
}
