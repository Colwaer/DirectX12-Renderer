#include "CubemapRTV.h"

CubemapRTV::CubemapRTV(ID3D12Device* device,
	UINT CubemapSize,
	CD3DX12_CPU_DESCRIPTOR_HANDLE cpuSrv,
	CD3DX12_GPU_DESCRIPTOR_HANDLE gpuSrv,
	DXGI_FORMAT rtvFormat,
	FLOAT* clearColor)
{
	md3dDevice = device;
	mCubemapSize = CubemapSize;
	SrvCpu = cpuSrv;
	SrvGpu = gpuSrv;
	SetViewportAndScissorRect(CubemapSize);
	mFormat = rtvFormat;
	for (int i = 0; i < 4; i++)
		mClearColor[i] = clearColor[i];
	SetDescriptorSize();
	ThrowIfFailed(mRtvHeap.Create(md3dDevice, D3D12_DESCRIPTOR_HEAP_TYPE_RTV, 6));
	BuildResources();
	BuildDescriptors();
}
void CubemapRTV::BuildResources()
{
	D3D12_RESOURCE_DESC texDesc;
	ZeroMemory(&texDesc, sizeof(D3D12_RESOURCE_DESC));
	texDesc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
	texDesc.Alignment = 0;
	texDesc.Width = mCubemapSize;
	texDesc.Height = mCubemapSize;
	texDesc.DepthOrArraySize = 6;
	texDesc.MipLevels = 1;
	texDesc.Format = mFormat;
	texDesc.SampleDesc.Count = 1;
	texDesc.SampleDesc.Quality = 0;
	texDesc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
	texDesc.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
	ThrowIfFailed(md3dDevice->CreateCommittedResource(&CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_DEFAULT), D3D12_HEAP_FLAG_NONE, &texDesc, D3D12_RESOURCE_STATE_GENERIC_READ, nullptr, IID_PPV_ARGS(&mResource)));
}
void CubemapRTV::BuildDescriptors()
{
	// Create 6 RTVs
	for (int i = 0; i < 6; i++)
	{
		D3D12_RENDER_TARGET_VIEW_DESC rtvDesc;
		rtvDesc.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2DARRAY;
		rtvDesc.Format = mFormat;
		rtvDesc.Texture2DArray.MipSlice = 0;
		rtvDesc.Texture2DArray.PlaneSlice = 0;
		rtvDesc.Texture2DArray.FirstArraySlice = (UINT)i;
		rtvDesc.Texture2DArray.ArraySize = 1;
		md3dDevice->CreateRenderTargetView(mResource.Get(), &rtvDesc, mRtvHeap.handleCPU((UINT)i));
	}
	
	// Create SRV
	D3D12_SHADER_RESOURCE_VIEW_DESC srvDesc;
	srvDesc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURECUBE;
	srvDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
	srvDesc.Format = mFormat;
	srvDesc.TextureCube.MipLevels = 1;
	srvDesc.TextureCube.MostDetailedMip = 0;
	srvDesc.TextureCube.ResourceMinLODClamp = 0.f;
	md3dDevice->CreateShaderResourceView(mResource.Get(), &srvDesc, SrvCpu);
}
void CubemapRTV::SetViewportAndScissorRect(UINT CubemapSize)
{
	mViewport.TopLeftX = 0.0f;
	mViewport.TopLeftY = 0.0f;
	mViewport.Width = (FLOAT)CubemapSize;
	mViewport.Height = (FLOAT)CubemapSize;
	mViewport.MinDepth = 0.0f;
	mViewport.MaxDepth = 1.0f;

	mScissorRect = { 0, 0, (int)(mViewport.Width), (int)(mViewport.Height) };
}

void CubemapRTV::SetDescriptorSize()
{
	SrvDescriptorSize = md3dDevice->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
	RtvDescriptorSize = md3dDevice->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
}
