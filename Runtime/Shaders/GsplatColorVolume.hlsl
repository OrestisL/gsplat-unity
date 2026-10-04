// Color Volume for gsplat-unity.
// Applies a colour and/or opacity transform to splats whose *model-space* centre
// falls inside a box / ellipsoid volume. The containment test mirrors
// GsplatCutout.hlsl (matrix convention: model-space -> volume-local space).
// SPDX-License-Identifier: MIT

#ifndef GSPLAT_COLOR_VOLUME_INCLUDED
#define GSPLAT_COLOR_VOLUME_INCLUDED

#define COLOR_VOLUME_TYPE_ELLIPSOID 0
#define COLOR_VOLUME_TYPE_BOX       1

// keep in sync with GsplatColorVolume.Op (C#)
#define COLOR_OP_REPLACE    0
#define COLOR_OP_MULTIPLY   1
#define COLOR_OP_ADD        2
#define COLOR_OP_HUESHIFT   3
#define COLOR_OP_SATURATION 4
#define COLOR_OP_BRIGHTNESS 5
#define COLOR_OP_CONTRAST   6
#define COLOR_OP_GRAYSCALE  7
#define COLOR_OP_INVERT     8
#define COLOR_OP_GAMMA      9

// keep in sync with GsplatColorVolume.OpacityMode (C#)
#define OPACITY_MODE_NONE     0
#define OPACITY_MODE_MULTIPLY 1
#define OPACITY_MODE_SET      2
#define OPACITY_MODE_ADD      3

struct ColorVolumeShaderData
{
    float4x4 mat;        // model-space -> volume-local space
    float4   color;      // tint / target colour (rgb)
    float4   params;     // x = strength (0..1 blend), y = colour amount, z = opacity amount, w spare
    uint     typeAndOp;  // bits 0-7 type, 8-15 colour op, bit 16 invert, bits 24-27 opacity mode
};

uint _ColorVolumesCount;
StructuredBuffer<ColorVolumeShaderData> _ColorVolumesBuffer;

float3 CV_RgbToHsv(float3 c)
{
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 CV_HsvToRgb(float3 c)
{
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
}

float3 CV_ApplyColorOp(uint op, float3 rgb, float4 color, float amt)
{
    if (op == COLOR_OP_REPLACE)    return color.rgb;
    if (op == COLOR_OP_MULTIPLY)   return rgb * color.rgb;
    if (op == COLOR_OP_ADD)        return rgb + color.rgb;
    if (op == COLOR_OP_HUESHIFT)   { float3 h = CV_RgbToHsv(rgb); h.x = frac(h.x + amt); return CV_HsvToRgb(h); }
    if (op == COLOR_OP_SATURATION) { float3 h = CV_RgbToHsv(rgb); h.y = saturate(h.y * amt); return CV_HsvToRgb(h); }
    if (op == COLOR_OP_BRIGHTNESS) return rgb * amt;
    if (op == COLOR_OP_CONTRAST)   return (rgb - 0.5) * amt + 0.5;
    if (op == COLOR_OP_GRAYSCALE)  return dot(rgb, float3(0.299, 0.587, 0.114)).xxx;
    if (op == COLOR_OP_INVERT)     return 1.0 - rgb;
    if (op == COLOR_OP_GAMMA)      return pow(max(rgb, 0.0), amt);
    return rgb;
}

float CV_ApplyOpacityOp(uint mode, float a, float amt)
{
    if (mode == OPACITY_MODE_MULTIPLY) return a * amt;
    if (mode == OPACITY_MODE_SET)      return amt;
    if (mode == OPACITY_MODE_ADD)      return a + amt;
    return a;
}

// modelPos: splat centre in model space (i.e. _PositionBuffer[id], pre _MATRIX_M)
// color.rgb = colour, color.w = opacity. Both may be edited.
void ApplyColorVolumes(float3 modelPos, inout float4 color)
{
    for (uint i = 0; i < _ColorVolumesCount; ++i)
    {
        ColorVolumeShaderData v = _ColorVolumesBuffer[i];
        uint type = v.typeAndOp & 0xFFu;
        if (type == 0xFFu)
            continue; // disabled sentinel

        uint colorOp = (v.typeAndOp >> 8u) & 0xFFu;
        bool invert = (v.typeAndOp & 0x10000u) != 0u;
        uint opacityMode = (v.typeAndOp >> 24u) & 0xFu;

        float3 local = mul(v.mat, float4(modelPos, 1.0)).xyz;

        // normalised distance from the volume centre: 0 at centre, 1 at the surface
        float d = (type == COLOR_VOLUME_TYPE_ELLIPSOID)
            ? length(local)
            : max(max(abs(local.x), abs(local.y)), abs(local.z));

        // feather = fraction of the volume used as a soft edge (params.w, 0 = hard)
        float feather = saturate(v.params.w);
        float inner = 1.0 - feather;

        // 1 inside the core, ramps to 0 at the surface
        float mask = 1.0 - smoothstep(inner, 1.0, d);
        if (invert)
            mask = 1.0 - mask; // fade the *outside* instead

        if (mask <= 0.0)
            continue;

        float strength = saturate(v.params.x) * mask; // blend scaled by the falloff

        // colour
        float3 edited = CV_ApplyColorOp(colorOp, color.rgb, v.color, v.params.y);
        color.rgb = lerp(color.rgb, edited, strength);

        // opacity
        if (opacityMode != OPACITY_MODE_NONE)
        {
            float a = CV_ApplyOpacityOp(opacityMode, color.w, v.params.z);
            color.w = lerp(color.w, saturate(a), strength);
        }
    }
}
#endif
