#include <windows.h>
#include <filesystem>

int WINAPI WinMain(HINSTANCE, HINSTANCE, LPSTR, int) {
    wchar_t launcherPath[MAX_PATH];
    GetModuleFileNameW(nullptr, launcherPath, MAX_PATH);

    std::filesystem::path folder =
        std::filesystem::path(launcherPath).parent_path();

    std::filesystem::path edopro = folder / L"EDOPro.exe";

    std::wstring command =
        L"\"" + edopro.wstring() +
        L"\" -u \"https://appealing-joy-production-bc20.up.railway.app/client-update\"";

    STARTUPINFOW si{};
    PROCESS_INFORMATION pi{};
    si.cb = sizeof(si);

    std::wstring mutableCommand = command;

    if(CreateProcessW(
        nullptr,
        mutableCommand.data(),
        nullptr,
        nullptr,
        FALSE,
        0,
        nullptr,
        folder.c_str(),
        &si,
        &pi
    )) {
        CloseHandle(pi.hProcess);
        CloseHandle(pi.hThread);
        return 0;
    }

    MessageBoxW(
        nullptr,
        L"EDOPro.exe could not be found or started.",
        L"Realm of Kings",
        MB_OK | MB_ICONERROR
    );

    return 1;
}
