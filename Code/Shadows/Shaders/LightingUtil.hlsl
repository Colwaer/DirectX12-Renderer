//***************************************************************************************
// LightingUtil.hlsl by Frank Luna (C) 2015 All Rights Reserved.
//
// Contains API for shader lighting.
//***************************************************************************************

#define MaxLights 16

// Numeric constants
static const float PI = 3.14159265;

struct Light
{
    float3 Strength;
    float FalloffStart; // point/spot light only
    float3 Direction;   // directional/spot light only
    float FalloffEnd;   // point/spot light only
    float3 Position;    // point light only
    float SpotPower;    // spot light only
};

struct Material
{
    float4 DiffuseAlbedo;
    float3 FresnelR0;
    float Metalness;
    float Roughness;
};

float CalcAttenuation(float d, float falloffStart, float falloffEnd)
{
    // Linear falloff.
    return saturate((falloffEnd-d) / (falloffEnd - falloffStart));
}

// Schlick gives an approximation to Fresnel reflectance (see pg. 233 "Real-Time Rendering 3rd Ed.").
// R0 = ( (n-1)/(n+1) )^2, where n is the index of refraction.
float3 SchlickFresnel(float3 R0, float3 h, float3 v)
{
    float cosIncidentAngle = saturate(dot(h, v));

    float f0 = 1.0f - cosIncidentAngle;
    float3 reflectPercent = R0 + (1.0f - R0)*(f0*f0*f0*f0*f0);

    return reflectPercent;
}
// GGX specular D (normal distribution)
float Specular_D_GGX(float NdotH, float roughness)
{
    float alpha = roughness * roughness;
    float alphaSqr = max(alpha * alpha, 0.0001);
    float lower = NdotH * NdotH * (alphaSqr - 1) + 1;
    return alphaSqr / max(1e-6, PI * lower * lower);
}
// K_direct is  (roughness + 1)^2 / 8    K_IBL is (roughness)^2 / 2
float G_Schlick_GGX(float3 n, float3 v, float k)
{
    float NdotV = max(dot(n, v), 0.f);
    //float NdotV = dot(n, v);
    return NdotV / (NdotV * (1 - k) + k);
}
// 光线入射和出射到眼睛各有一次遮蔽
float G_InAndOutSum(float3 n, float3 v, float3 l, float k)
{
    return G_Schlick_GGX(n, v, k) * G_Schlick_GGX(n, l, k);
}
float3 LambertDiffuse(float3 kS, float3 albedo, float metalness)
{
    float3 kD = (float3(1.0f, 1.0f, 1.0f) - kS) * (1 - metalness);
    return (kD * albedo);
}
// Cook-Torrance Specular
float3 CookTorrance(float3 n, float3 l, float3 v, float roughness, float metalness, float3 f0, out float3 kS)
{
    float3 h = normalize(v + l);

    float D = Specular_D_GGX(max(dot(n, h), 0.f), roughness);
    float3 F = SchlickFresnel(f0, v, h);
    float G = G_InAndOutSum(n, v, l, (roughness + 1) * (roughness + 1) / 8.f);
    kS = F;
    float NdotV = max(dot(n, v), 0.0f);
    float NdotL = max(dot(n, l), 0.0f);
    return (D * F * G) / (4 * max(NdotV * NdotL, 0.01f));
}

float3 DirectPBR(float3 lightStrength, float3 lightVec, float3 normal, float3 toEye, Material mat)
{
    float3 kS = float3(0, 0, 0);
    float3 albedo = mat.DiffuseAlbedo.rgb;
    
    // cookTorrance算出了kS
    float3 specBRDF = CookTorrance(normal, lightVec, toEye, mat.Roughness, mat.Metalness, mat.FresnelR0, kS);
    float3 diffBRDF = LambertDiffuse(kS, albedo, mat.Metalness);

    // 这个已经乘过了
    // float NdotL = max(dot(normal, lightStrength), 0.f);
    
    return (diffBRDF + specBRDF) * lightStrength;
}


float3 BlinnPhong(float3 lightStrength, float3 lightVec, float3 normal, float3 toEye, Material mat)
{
    const float m = mat.Roughness * 256.0f;
    float3 halfVec = normalize(toEye + lightVec);

    float roughnessFactor = (m + 8.0f)*pow(max(dot(halfVec, normal), 0.0f), m) / 8.0f;
    float3 fresnelFactor = SchlickFresnel(mat.FresnelR0, halfVec, lightVec);

    float3 specAlbedo = fresnelFactor*roughnessFactor;

    // Our spec formula goes outside [0,1] range, but we are 
    // doing LDR rendering.  So scale it down a bit.
    specAlbedo = specAlbedo / (specAlbedo + 1.0f);

    return (mat.DiffuseAlbedo.rgb + specAlbedo) * lightStrength;
}

//---------------------------------------------------------------------------------------
// Evaluates the lighting equation for directional lights.
//---------------------------------------------------------------------------------------
float3 ComputeDirectionalLight(Light L, Material mat, float3 normal, float3 toEye)
{
    // The light vector aims opposite the direction the light rays travel.
    float3 lightVec = -L.Direction;

    // Scale light down by Lambert's cosine law.
    float ndotl = max(dot(lightVec, normal), 0.0f);
    float3 lightStrength = L.Strength * ndotl;

    return DirectPBR(lightStrength, lightVec, normal, toEye, mat);
}

//---------------------------------------------------------------------------------------
// Evaluates the lighting equation for point lights.
//---------------------------------------------------------------------------------------
float3 ComputePointLight(Light L, Material mat, float3 pos, float3 normal, float3 toEye)
{
    // The vector from the surface to the light.
    float3 lightVec = L.Position - pos;

    // The distance from surface to light.
    float d = length(lightVec);

    // Range test.
    if(d > L.FalloffEnd)
        return 0.0f;

    // Normalize the light vector.
    lightVec /= d;

    // Scale light down by Lambert's cosine law.
    float ndotl = max(dot(lightVec, normal), 0.0f);
    float3 lightStrength = L.Strength * ndotl;

    // Attenuate light by distance.
    float att = CalcAttenuation(d, L.FalloffStart, L.FalloffEnd);
    lightStrength *= att;

    return BlinnPhong(lightStrength, lightVec, normal, toEye, mat);
}

//---------------------------------------------------------------------------------------
// Evaluates the lighting equation for spot lights.
//---------------------------------------------------------------------------------------
float3 ComputeSpotLight(Light L, Material mat, float3 pos, float3 normal, float3 toEye)
{
    // The vector from the surface to the light.
    float3 lightVec = L.Position - pos;

    // The distance from surface to light.
    float d = length(lightVec);

    // Range test.
    if(d > L.FalloffEnd)
        return 0.0f;

    // Normalize the light vector.
    lightVec /= d;

    // Scale light down by Lambert's cosine law.
    float ndotl = max(dot(lightVec, normal), 0.0f);
    float3 lightStrength = L.Strength * ndotl;

    // Attenuate light by distance.
    float att = CalcAttenuation(d, L.FalloffStart, L.FalloffEnd);
    lightStrength *= att;

    // Scale by spotlight
    float spotFactor = pow(max(dot(-lightVec, L.Direction), 0.0f), L.SpotPower);
    lightStrength *= spotFactor;

    return BlinnPhong(lightStrength, lightVec, normal, toEye, mat);
}

float4 ComputeLighting(Light gLights[MaxLights], Material mat,
                       float3 pos, float3 normal, float3 toEye,
                       float3 shadowFactor)
{
    float3 result = 0.0f;

    int i = 0;

#if (NUM_DIR_LIGHTS > 0)
    for(i = 0; i < NUM_DIR_LIGHTS; ++i)
    {
        result += shadowFactor[i] * ComputeDirectionalLight(gLights[i], mat, normal, toEye);
    }
#endif

#if (NUM_POINT_LIGHTS > 0)
    for(i = NUM_DIR_LIGHTS; i < NUM_DIR_LIGHTS+NUM_POINT_LIGHTS; ++i)
    {
        result += ComputePointLight(gLights[i], mat, pos, normal, toEye);
    }
#endif

#if (NUM_SPOT_LIGHTS > 0)
    for(i = NUM_DIR_LIGHTS + NUM_POINT_LIGHTS; i < NUM_DIR_LIGHTS + NUM_POINT_LIGHTS + NUM_SPOT_LIGHTS; ++i)
    {
        result += ComputeSpotLight(gLights[i], mat, pos, normal, toEye);
    }
#endif 

    return float4(result, 0.0f);
}


