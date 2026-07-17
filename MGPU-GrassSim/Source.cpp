#include "HybridGrassSimApp.h"
#include <cstring>
#include <exception>
#include <fstream>
#include <string>
using namespace Common;

namespace
{
    void BootLog(const char* step)
    {
        try
        {
            std::ofstream f("grasssim-boot.log", std::ios::app);
            f << step << "\n";
            f.flush();
        }
        catch (...)
        {
        }
        OutputDebugStringA(step);
        OutputDebugStringA("\n");
    }
}

int WINAPI WinMain(const HINSTANCE hInstance, HINSTANCE prevInstance,
                   PSTR cmdLine, int showCmd)
{
    // Enable run-time memory check for debug builds.
#if defined(DEBUG) | defined(_DEBUG)
    _CrtSetDbgFlag(_CRTDBG_ALLOC_MEM_DF | _CRTDBG_LEAK_CHECK_DF);
#endif

    try
    {
        {
            std::ofstream f("grasssim-boot.log", std::ios::trunc);
            f << "WinMain start\n";
        }
        BootLog("creating HybridGrassSimApp");
        HybridGrassSimApp theApp(hInstance);
        if (cmdLine && strstr(cmdLine, "--perf-sweep") != nullptr)
        {
            theApp.EnablePerformanceSweepMode(4, 12);
        }
        else if (cmdLine && strstr(cmdLine, "--perf-test") != nullptr)
        {
            theApp.EnablePerformanceTestMode(5, 20);
        }
        BootLog("calling Initialize");
        if (!theApp.Initialize())
        {
            BootLog("Initialize returned false");
            MessageBoxA(nullptr, "Initialize() returned false. See grasssim-boot.log next to the exe.",
                        "MGPU-GrassSim", MB_OK | MB_ICONERROR);
            return 0;
        }

        BootLog("Initialize OK, entering Run");
        auto result = theApp.Run();
        BootLog("Run returned");
        return result;
    }
    catch (DxException& e)
    {
        BootLog("DxException");
        MessageBox(nullptr, e.ToString().c_str(), L"HR Failed", MB_OK);
        return 0;
    }
    catch (const std::exception& e)
    {
        BootLog(e.what());
        MessageBoxA(nullptr, e.what(), "Error", MB_OK);
        return 0;
    }
    catch (...)
    {
        BootLog("unknown exception");
        MessageBoxA(nullptr, "Unknown exception during startup", "MGPU-GrassSim", MB_OK | MB_ICONERROR);
        return 0;
    }
}
