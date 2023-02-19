#include "Common.hlsl"

struct VertexIn
{
    float3 PosL : POSITION;
    float3 NormalL : NORMAL;
    float2 TexC : TEXCOORD;
};

struct VertexOut
{
    float4 PosH : SV_POSITION;
    float3 PosL : POSITION;
};

float4 PS(VertexOut pin) : SV_Target
{
    float3 color = float3(0, 0, 0);
	if (pin.PosL.x > 1000.f)
        color.r = 1;
	else
        color.g = 1;
    return float4(pin.PosL * 10000, 1);
    //return gCubeMap.Sample(gsamLinearWrap, pin.PosL);
	float3 irradiance = float3(0.0f, 0.0f, 0.0f);

	float3 normal = normalize(pin.PosL);
	float3 up = float3(0.0, 1.0, 0.0);
	float3 right = cross(up, normal);
	up = cross(normal, right);

	float sampleDelta = 0.08f;
	float numSamples = 0.0f;
	for (float phi = 0.0f; phi < 2.0f * PI; phi += sampleDelta)
	{
		for (float theta = 0.0; theta < 0.5 * PI; theta += sampleDelta)
		{
			// spherical to cartesian (in tangent space)
			float3 tangentSample = float3(sin(theta) * cos(phi),  sin(theta) * sin(phi), cos(theta));
			// tangent space to world
			float3 sampleVec = tangentSample.x * right + tangentSample.y * up + tangentSample.z * normal;
			
			irradiance += gCubeMap.Sample(gsamAnisotropicClamp, sampleVec).rgb * cos(theta) * sin(theta);
			numSamples++;
		}
	}
	irradiance = PI * irradiance * (1.0f / numSamples);

	return float4(irradiance, 1.0f);
}