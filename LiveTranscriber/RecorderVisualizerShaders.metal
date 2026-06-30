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

static float sampleHistory(float normalizedX, constant float *history, uint count) {
    if (count == 0) {
        return 0.0;
    }

    float scaledIndex = clamp(normalizedX, 0.0, 1.0) * float(count - 1);
    uint leftIndex = uint(floor(scaledIndex));
    uint rightIndex = min(leftIndex + 1, count - 1);
    return mix(history[leftIndex], history[rightIndex], fract(scaledIndex));
}

static float lineGlow(float y, float targetY, float coreWidth, float glowWidth) {
    float distanceFromLine = abs(y - targetY);
    float core = 1.0 - smoothstep(coreWidth, coreWidth + 0.010, distanceFromLine);
    float glow = 1.0 - smoothstep(coreWidth, glowWidth, distanceFromLine);
    return max(core, glow * 0.42);
}

fragment float4 recorderVisualizerFragment(
    RecorderVisualizerVertexOut in [[stage_in]],
    constant RecorderVisualizerUniforms &uniforms [[buffer(0)]],
    constant float *levelHistory [[buffer(1)]]
) {
    float2 uv = clamp(in.uv, 0.0, 1.0);
    float active = uniforms.active;
    float level = clamp(uniforms.level, 0.0, 1.0);
    float time = uniforms.time;

    float2 center = uv - float2(0.5, 0.50);
    float vignette = smoothstep(0.94, 0.20, length(center));
    float edgeFalloff = smoothstep(0.010, 0.120, uv.x) *
        smoothstep(0.990, 0.880, uv.x) *
        smoothstep(0.010, 0.150, uv.y) *
        smoothstep(0.990, 0.850, uv.y);

    float3 deepInk = float3(0.024, 0.026, 0.031);
    float3 warmInk = float3(0.080, 0.035, 0.032);
    float3 coolInk = float3(0.028, 0.045, 0.064);
    float3 color = mix(deepInk, warmInk, 0.46 + active * 0.12);
    color = mix(color, coolInk, smoothstep(0.18, 1.0, uv.x) * 0.28);
    color *= 0.70 + vignette * 0.48;
    color *= 0.76 + edgeFalloff * 0.30;

    float3 accent = uniforms.tint.rgb;
    float3 coolAccent = float3(0.10, 0.42, 0.86);

    float radialWarm = smoothstep(0.78, 0.05, distance(uv, float2(0.23, 0.64)));
    float radialCool = smoothstep(0.84, 0.08, distance(uv, float2(0.80, 0.30)));
    color += accent * radialWarm * (0.060 + active * 0.050);
    color += coolAccent * radialCool * 0.040;

    float glassHighlight = smoothstep(0.22, 0.0, abs(uv.y - 0.16)) *
        smoothstep(0.0, 0.45, uv.x) *
        (1.0 - smoothstep(0.62, 1.0, uv.x));
    color += float3(1.0, 0.74, 0.55) * glassHighlight * 0.045;

    float diagonalSweep = 1.0 - smoothstep(0.010, 0.150, abs((uv.y - 0.20) - (uv.x - 0.14) * 0.42));
    color += float3(1.0, 0.72, 0.52) * diagonalSweep * 0.030;

    float verticalGrid = 1.0 - smoothstep(0.004, 0.012, abs(fract(uv.x * 18.0) - 0.5));
    float horizontalGrid = 1.0 - smoothstep(0.004, 0.012, abs(fract(uv.y * 8.0) - 0.5));
    float gridFade = smoothstep(0.08, 0.25, uv.x) *
        smoothstep(0.92, 0.72, uv.x) *
        smoothstep(0.20, 0.36, uv.y) *
        smoothstep(0.94, 0.72, uv.y);
    color += coolAccent * max(verticalGrid, horizontalGrid) * gridFade * 0.020;

    float historyLevel = sampleHistory(uv.x, levelHistory, uniforms.historyCount);
    float previousLevel = sampleHistory(max(uv.x - 0.012, 0.0), levelHistory, uniforms.historyCount);
    float nextLevel = sampleHistory(min(uv.x + 0.012, 1.0), levelHistory, uniforms.historyCount);
    float localPeak = max(historyLevel, max(previousLevel, nextLevel));
    float envelope = pow(clamp(localPeak, 0.0, 1.0), 0.78);
    float flutter = sin(uv.x * 18.0 + time * 1.6) * active * (0.006 + level * 0.011);

    float centerLineY = 0.610;
    float upperY = centerLineY - envelope * 0.330 + flutter;
    float lowerY = centerLineY + envelope * 0.210 - flutter * 0.62;
    float middleY = centerLineY + sin(uv.x * 10.0 - time * 0.55) * 0.006 * active * (0.25 + level);

    float upperWave = lineGlow(uv.y, upperY, 0.004, 0.095);
    float lowerWave = lineGlow(uv.y, lowerY, 0.004, 0.070);
    float middleWave = lineGlow(uv.y, middleY, 0.002, 0.035);
    float ribbon = smoothstep(upperY - 0.030, upperY + 0.010, uv.y) *
        smoothstep(lowerY + 0.030, lowerY - 0.010, uv.y);

    float waveformFade = smoothstep(0.045, 0.160, uv.x) *
        smoothstep(0.985, 0.840, uv.x);
    color += accent * ribbon * waveformFade * (0.030 + active * 0.045);
    color += accent * upperWave * waveformFade * (0.105 + active * 0.160);
    color += mix(accent, coolAccent, 0.35) * lowerWave * waveformFade * (0.052 + active * 0.070);
    color += float3(1.0, 0.42, 0.26) * upperWave * waveformFade * level * active * 0.080;
    color += coolAccent * middleWave * waveformFade * 0.036;

    float latestPulse = 1.0 - smoothstep(0.0, 0.045, abs(uv.x - 0.955));
    latestPulse *= smoothstep(0.92, 0.98, uv.x);
    color += accent * latestPulse * (0.020 + level * active * 0.060);

    float scanline = 0.5 + 0.5 * sin(uv.y * uniforms.size.y * 0.62);
    float grain = hash11(uv.x * uniforms.size.x + uv.y * uniforms.size.y * 17.0 + time) - 0.5;
    color -= scanline * 0.006;
    color += grain * 0.014;

    return float4(color, 1.0);
}
