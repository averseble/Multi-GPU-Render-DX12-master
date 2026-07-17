#pragma once
#include <d3dcompiler.h>
#include <filesystem>
#include <fstream>
#include <string>
#include <Windows.h>

#include "d3dUtil.h"

namespace PEPEngine::Graphics
{
    using namespace Utils;

    /// Resolves paths like Shaders\\Foo.hlsl when the process cwd is not the project/output directory.
    inline std::wstring ResolveShaderFilePath(const std::wstring& filename)
    {
        namespace fs = std::filesystem;

        try
        {
            const fs::path normalized = fs::path(filename).lexically_normal();

            if (!normalized.empty() && normalized.is_absolute() && fs::exists(normalized))
            {
                return normalized.wstring();
            }

            if (!normalized.empty() && fs::exists(normalized))
            {
                return fs::weakly_canonical(normalized).wstring();
            }

            const fs::path fromCwd = (fs::current_path() / normalized).lexically_normal();
            if (fs::exists(fromCwd))
            {
                return fs::weakly_canonical(fromCwd).wstring();
            }

            wchar_t moduleBuf[MAX_PATH]{};
            const DWORD nChars = GetModuleFileNameW(nullptr, moduleBuf, MAX_PATH);
            if (nChars != 0 && nChars < MAX_PATH)
            {
                fs::path dir = fs::path(moduleBuf).parent_path();
                for (int depth = 0; depth < 24 && !dir.empty(); ++depth)
                {
                    const fs::path candidate = (dir / normalized).lexically_normal();
                    if (fs::exists(candidate))
                    {
                        return fs::weakly_canonical(candidate).wstring();
                    }

                    if (!dir.has_parent_path())
                    {
                        break;
                    }
                    fs::path parent = dir.parent_path();
                    if (parent == dir)
                    {
                        break;
                    }
                    dir = std::move(parent);
                }
            }
        }
        catch (...)
        {
            // Fall through and return original path for D3D error output.
        }

        return filename;
    }

    ComPtr<ID3DBlob> LoadBinary(const std::wstring& filename)
    {
        std::ifstream fin(filename, std::ios::binary);

        fin.seekg(0, std::ios_base::end);
        std::ifstream::pos_type size = static_cast<int>(fin.tellg());
        fin.seekg(0, std::ios_base::beg);

        ComPtr<ID3DBlob> blob;
        ThrowIfFailed(D3DCreateBlob(size, blob.GetAddressOf()));

        fin.read(static_cast<char*>(blob->GetBufferPointer()), size);
        fin.close();

        return blob;
    }

    ComPtr<ID3D12Resource> CreateDefaultBuffer(
        ID3D12Device* device,
        ID3D12GraphicsCommandList* commandList,
        const void* initData,
        const UINT64 byteSize,
        ComPtr<ID3D12Resource>& uploadBuffer)
    {
        ComPtr<ID3D12Resource> defaultBuffer;

        // Create the actual default buffer resource.
        ThrowIfFailed(device->CreateCommittedResource(
            &CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_DEFAULT),
            D3D12_HEAP_FLAG_NONE,
            &CD3DX12_RESOURCE_DESC::Buffer(byteSize),
            D3D12_RESOURCE_STATE_COMMON,
            nullptr,
            IID_PPV_ARGS(defaultBuffer.GetAddressOf())));

        // In order to copy CPU memory data into our default buffer, we need to create
        // an intermediate upload heap. 
        ThrowIfFailed(device->CreateCommittedResource(
            &CD3DX12_HEAP_PROPERTIES(D3D12_HEAP_TYPE_UPLOAD),
            D3D12_HEAP_FLAG_NONE,
            &CD3DX12_RESOURCE_DESC::Buffer(byteSize),
            D3D12_RESOURCE_STATE_GENERIC_READ,
            nullptr,
            IID_PPV_ARGS(uploadBuffer.GetAddressOf())));


        // Describe the data we want to copy into the default buffer.
        D3D12_SUBRESOURCE_DATA subResourceData = {};
        subResourceData.pData = initData;
        subResourceData.RowPitch = byteSize;
        subResourceData.SlicePitch = subResourceData.RowPitch;

        // Schedule to copy the data to the default buffer resource.  At a high level, the helper function UpdateSubresources
        // will copy the CPU memory into the intermediate upload heap.  Then, using ID3D12CommandList::CopySubresourceRegion,
        // the intermediate upload heap data will be copied to mBuffer.
        commandList->ResourceBarrier(1, &CD3DX12_RESOURCE_BARRIER::Transition(defaultBuffer.Get(),
                                                                              D3D12_RESOURCE_STATE_COMMON,
                                                                              D3D12_RESOURCE_STATE_COPY_DEST));
        UpdateSubresources<1>(commandList, defaultBuffer.Get(), uploadBuffer.Get(), 0, 0, 1, &subResourceData);
        commandList->ResourceBarrier(1, &CD3DX12_RESOURCE_BARRIER::Transition(defaultBuffer.Get(),
                                                                              D3D12_RESOURCE_STATE_COPY_DEST,
                                                                              D3D12_RESOURCE_STATE_GENERIC_READ));

        // Note: uploadBuffer has to be kept alive after the above function calls because
        // the command list has not been executed yet that performs the actual copy.
        // The caller can Release the uploadBuffer after it knows the copy has been executed.


        return defaultBuffer;
    }

    ComPtr<ID3DBlob> CompileShader(
        const std::wstring& filename,
        const D3D_SHADER_MACRO* defines,
        const std::string& entrypoint,
        const std::string& target)
    {
        UINT compileFlags = D3DCOMPILE_ENABLE_UNBOUNDED_DESCRIPTOR_TABLES | D3DCOMPILE_ALL_RESOURCES_BOUND;

#if defined(DEBUG) || defined(_DEBUG)
        compileFlags |= D3DCOMPILE_DEBUG | D3DCOMPILE_SKIP_OPTIMIZATION;
#endif

        HRESULT hr = S_OK;

        const std::wstring resolved = ResolveShaderFilePath(filename);

        ComPtr<ID3DBlob> byteCode = nullptr;
        ComPtr<ID3DBlob> errors;
        hr = D3DCompileFromFile(resolved.c_str(), defines, D3D_COMPILE_STANDARD_FILE_INCLUDE,
                                entrypoint.c_str(), target.c_str(), compileFlags, 0, &byteCode, &errors);

        std::string errorText;
        if (errors != nullptr)
        {
            errorText.assign(static_cast<char*>(errors->GetBufferPointer()),
                             errors->GetBufferSize());
            OutputDebugStringA(errorText.c_str());
        }

        if (FAILED(hr))
        {
            std::wstring message = L"D3DCompileFromFile failed\nrequested: " + filename +
                L"\nresolved: " + resolved +
                L"\nentry: " + AnsiToWString(entrypoint) +
                L"\ntarget: " + AnsiToWString(target);
            if (!errorText.empty())
            {
                message += L"\n\ncompiler output:\n" + AnsiToWString(errorText);
            }
            else
            {
                message += L"\n\n(no compiler output — usually file not found or include path failed)";
                message += L"\ncwd: " + std::filesystem::current_path().wstring();
            }
            throw DxException(hr, L"D3DCompileFromFile", AnsiToWString(__FILE__), __LINE__, message);
        }

        return byteCode;
    }
}
