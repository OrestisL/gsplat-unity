// Color Volume for gsplat-unity.
// A box / ellipsoid volume that recolours and/or re-opacifies the splats inside
// it. Mirrors the structure of GsplatCutout so the matrix convention and
// registration pattern are the same.
// SPDX-License-Identifier: MIT

using System.Collections.Generic;
using Unity.Collections.LowLevel.Unsafe;
using UnityEngine;
#if UNITY_EDITOR
using UnityEditor;
#endif

namespace Gsplat
{
    [ExecuteInEditMode]
    public class GsplatColorVolume : MonoBehaviour
    {
        public enum Type { Ellipsoid, Box }

        // keep in sync with the COLOR_OP_* defines in GsplatColorVolume.hlsl
        public enum Op
        {
            Replace, Multiply, Add, HueShift, Saturation,
            Brightness, Contrast, Grayscale, Invert, Gamma
        }

        // keep in sync with the OPACITY_MODE_* defines in GsplatColorVolume.hlsl
        public enum OpacityMode { None, Multiply, Set, Add }

        public bool m_Invert = false;
        public Type m_Type = Type.Box;

        [Header("Colour")]
        public Op m_Op = Op.Multiply;

        [Tooltip("Tint / target colour. Used by Replace, Multiply and Add.")]
        [ColorUsage(false, true)] public Color m_Color = Color.white;

        [Tooltip("Op amount: HueShift = turns (0..1), Saturation/Brightness/Contrast/Gamma = factor. Ignored by Replace/Multiply/Add/Grayscale/Invert.")]
        public float m_Amount = 1f;

        [Header("Opacity")]
        public OpacityMode m_OpacityMode = OpacityMode.None;

        [Tooltip("Multiply: factor (0..1 fades out). Set: absolute opacity (0..1). Add: delta (may be negative).")]
        public float m_OpacityAmount = 1f;

        [Header("Blend")]
        [Tooltip("Blend between the original and edited colour/opacity.")]
        [Range(0f, 1f)] public float m_Strength = 1f;

        [Header("Edge")]
        [Tooltip("Soft edge as a fraction of the volume: 0 = hard, 1 = fades from the centre.")]
        [Range(0f, 1f)] public float m_Feather = 0.25f;
        public struct ShaderData
        {
            public Matrix4x4 matrix;     // model-space -> volume-local
            public Vector4 color;
            public Vector4 parameters;   // x = strength, y = colour amount, z = opacity amount
            public uint typeAndOp;       // type | op<<8 | invert<<16 | opacityMode<<24
        }

        public static int ShaderDataSize => UnsafeUtility.SizeOf<ShaderData>();
        public static readonly List<GsplatColorVolume> m_Registered = new();

        void OnEnable()
        {
            if (!m_Registered.Contains(this)) m_Registered.Add(this);
        }

        void OnDisable()
        {
            m_Registered.Remove(this);
        }

        // rendererMatrix is the renderer's localToWorldMatrix (== _MATRIX_M).
        public ShaderData GetShaderData(Matrix4x4 rendererMatrix)
        {
            ShaderData sd = default;
            if (isActiveAndEnabled)
            {
                sd.matrix = transform.worldToLocalMatrix * rendererMatrix;
                sd.color = m_Color;
                sd.parameters = new Vector4(m_Strength, m_Amount, m_OpacityAmount, m_Feather);
                sd.typeAndOp = ((uint)m_Type)
                             | (((uint)m_Op) << 8)
                             | (m_Invert ? 0x10000u : 0u)
                             | (((uint)m_OpacityMode) << 24);

            }
            else
            {
                sd.typeAndOp = 0xFFu; // disabled sentinel, skipped in the shader
            }
            return sd;
        }

#if UNITY_EDITOR
        void OnDrawGizmos()
        {
            Gizmos.matrix = transform.localToWorldMatrix;
            Color c = m_Color;
            c.a = Selection.Contains(gameObject) ? 0.9f : 0.25f;
            Gizmos.color = c;
            if (m_Type == Type.Ellipsoid) Gizmos.DrawWireSphere(Vector3.zero, 1f);
            else Gizmos.DrawWireCube(Vector3.zero, Vector3.one * 2f);
        }
#endif
    }
}
