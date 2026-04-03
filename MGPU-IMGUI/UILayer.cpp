#include "UILayer.h"

#include <utility>


#include "GCommandList.h"
#include "GCommandQueue.h"
#include "GDescriptorHeap.h"

// Forward declare message handler from imgui_impl_win32.cpp
extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

void UILayer_ImGuiSrvAllocFn(ImGui_ImplDX12_InitInfo* info, D3D12_CPU_DESCRIPTOR_HANDLE* out_cpu_handle,
                             D3D12_GPU_DESCRIPTOR_HANDLE* out_gpu_handle)
{
    auto* layer = static_cast<UILayer*>(info->UserData);
    IM_ASSERT(layer != nullptr && !layer->imguiFontDescriptorInUse);
    layer->imguiFontDescriptorInUse = true;
    *out_cpu_handle = layer->srvMemory.GetCPUHandle(0);
    *out_gpu_handle = layer->srvMemory.GetGPUHandle(0);
}

void UILayer_ImGuiSrvFreeFn(ImGui_ImplDX12_InitInfo* info, D3D12_CPU_DESCRIPTOR_HANDLE,
                            D3D12_GPU_DESCRIPTOR_HANDLE)
{
    auto* layer = static_cast<UILayer*>(info->UserData);
    IM_ASSERT(layer != nullptr && layer->imguiFontDescriptorInUse);
    layer->imguiFontDescriptorInUse = false;
}

LRESULT UILayer::MsgProc(const HWND hwnd, const UINT msg, const WPARAM wParam, const LPARAM lParam)
{
    if (ImGui_ImplWin32_WndProcHandler(hwnd, msg, wParam, lParam))
        return true;
}


void UILayer::SetupRenderBackends()
{
    srvMemory = device->AllocateDescriptors(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, globalCountFrameResources);
    imguiFontDescriptorInUse = false;

    ImGui_ImplWin32_Init(this->hwnd);

    ImGui_ImplDX12_InitInfo init_info = {};
    init_info.Device = device->GetDXDevice().Get();
    init_info.CommandQueue = device->GetCommandQueue(GQueueType::Graphics)->GetD3D12CommandQueue().Get();
    init_info.NumFramesInFlight = globalCountFrameResources;
    init_info.RTVFormat = DXGI_FORMAT_R8G8B8A8_UNORM;
    init_info.DSVFormat = DXGI_FORMAT_UNKNOWN;
    init_info.UserData = this;
    {
        const std::shared_ptr<GDescriptorHeap> heap = srvMemory.GetDescriptorHeap();
        init_info.SrvDescriptorHeap = heap->GetDirectxHeap();
    }

    init_info.SrvDescriptorAllocFn = UILayer_ImGuiSrvAllocFn;
    init_info.SrvDescriptorFreeFn = UILayer_ImGuiSrvFreeFn;

    ImGui_ImplDX12_Init(&init_info);

    ImGui::StyleColorsDark();
}

void UILayer::Initialize()
{
    // Setup Dear ImGui context
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    //ImGuiIO& io = ImGui::GetIO(); (void)io;
    //io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
    //io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;      // Enable Gamepad Controls
    //

    SetupRenderBackends();
}

void UILayer::CreateDeviceObject()
{
    ImGui_ImplDX12_CreateDeviceObjects();
}

void UILayer::Invalidate()
{
    ImGui_ImplDX12_InvalidateDeviceObjects();
}

UILayer::UILayer(const std::shared_ptr<GDevice>& device, const HWND hwnd): hwnd(hwnd), device((device))
{
    Initialize();
    CreateDeviceObject();
}

UILayer::~UILayer()
{
    ImGui_ImplDX12_Shutdown();
    ImGui_ImplWin32_Shutdown();
    ImGui::DestroyContext();
}

void UILayer::ChangeDevice(const std::shared_ptr<GDevice>& device)
{
    if (this->device == device)
    {
        return;
    }
    this->device = device;

    Invalidate();
    SetupRenderBackends();
    CreateDeviceObject();
}


void UILayer::Render(const std::shared_ptr<GCommandList>& cmdList) const
{
    cmdList->SetDescriptorsHeap(&srvMemory);

    // Start the Dear ImGui frame
    ImGui_ImplDX12_NewFrame();
    ImGui_ImplWin32_NewFrame();
    ImGui::NewFrame();
    ImGui::ShowDemoWindow();
    ImGui::Render();
    ImGui_ImplDX12_RenderDrawData(ImGui::GetDrawData(), cmdList->GetGraphicsCommandList().Get());
}
