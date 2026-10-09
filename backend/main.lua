local logger = require("logger")
local millennium = require("millennium")

local ffi = require("ffi")

ffi.cdef[[
typedef int BOOL;
typedef unsigned long DWORD;
typedef long LONG;
typedef unsigned long ULONG;
typedef void* HANDLE;
typedef void* HWND;
typedef const wchar_t* LPCWSTR;
typedef wchar_t WCHAR;
typedef uintptr_t ULONG_PTR;
typedef intptr_t LONG_PTR;
typedef LONG_PTR LPARAM;
typedef unsigned int UINT;
typedef long HRESULT;
typedef int INT;
typedef size_t SIZE_T;
typedef char CHAR;
typedef CHAR *LPSTR;

HANDLE CreateToolhelp32Snapshot(DWORD dwFlags, DWORD th32ProcessID);
BOOL Process32FirstW(HANDLE hSnapshot, void* lppe);
BOOL Process32NextW(HANDLE hSnapshot, void* lppe);
BOOL CloseHandle(HANDLE hObject);

typedef struct {
    DWORD dwSize;
    DWORD cntUsage;
    DWORD th32ProcessID;
    ULONG_PTR th32DefaultHeapID;
    DWORD th32ModuleID;
    DWORD cntThreads;
    DWORD th32ParentProcessID;
    LONG pcPriClassBase;
    DWORD dwFlags;
    WCHAR szExeFile[260];
} PROCESSENTRY32W;

static const int TH32CS_SNAPPROCESS = 0x00000002;

typedef int (__stdcall *WNDENUMPROC)(HWND, LPARAM);
BOOL EnumWindows(WNDENUMPROC lpEnumFunc, LPARAM lParam);
DWORD GetWindowThreadProcessId(HWND hWnd, DWORD* lpdwProcessId);
int WideCharToMultiByte(UINT CodePage, DWORD dwFlags, const WCHAR *lpWideCharStr, int cchWideChar, char *lpMultiByteStr, int cbMultiByte, const char *lpDefaultChar, int *lpUsedDefaultChar);
HRESULT DwmSetWindowAttribute(HWND hwnd, DWORD dwAttribute, void* pvAttribute, DWORD cbAttribute);

typedef enum _WINDOWCOMPOSITIONATTRIB {
    WCA_ACCENT_POLICY = 19
} WINDOWCOMPOSITIONATTRIB;

typedef struct _ACCENTPOLICY {
    INT nAccentState;
    INT nFlags;
    DWORD nColor;
    INT nAnimationId;
} ACCENTPOLICY;

typedef struct _WINDOWCOMPOSITIONATTRIBDATA {
    WINDOWCOMPOSITIONATTRIB nAttribute;
    void* pData;
    SIZE_T ulDataSize;
} WINDOWCOMPOSITIONATTRIBDATA;

BOOL SetWindowCompositionAttribute(HWND hWnd, WINDOWCOMPOSITIONATTRIBDATA* data);
]]

local C = ffi.C
local user32 = ffi.load("user32")
local dwmapi = ffi.load("dwmapi")

local CP_UTF8 = 65001
local TH32CS_SNAPPROCESS = 0x00000002
local WCA_ACCENT_POLICY = 19
local ACCENT_ENABLE_BLURBEHIND = 3
local ACCENT_FLAG_ENABLE_BLURBEHIND = 0x20
local DWMWA_WINDOW_CORNER_PREFERENCE = 33
local DWMWCP_ROUND = 2

local IS_CORNER_PREFERENCE_COMPATIBLE = true
local IS_BLUR_BEHIND_COMPATIBLE = true

-- Global state for window enumeration
local current_target_pids = {}

-- Single reusable callback - created once and reused
local window_enum_callback = nil

-- cast wchar to utf8 string. 
-- 260 == MAX_PATH, we assume steam is not running from a path longer than that.
-- that is likely a safe assumption (I hope).
local function wchar_to_utf8(wstr)
    local outbuf = ffi.new("char[260]")
    local res = C.WideCharToMultiByte(CP_UTF8, 0, wstr, -1, outbuf, 260, nil, nil)
    if res == 0 then return nil end
    return ffi.string(outbuf)
end

-- find all process IDs matching the given executable name (case insensitive)
local function find_pids_by_name(exe_name)
    local pids = {}
    local snap = C.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if snap == ffi.cast("HANDLE", -1) then
        logger:error("CreateToolhelp32Snapshot failed")
        return pids
    end
    local success, result = pcall(function()
        local entry = ffi.new("PROCESSENTRY32W")
        entry.dwSize = ffi.sizeof(entry)

        local ok = C.Process32FirstW(snap, entry)
        while ok ~= 0 do
            local name = wchar_to_utf8(entry.szExeFile)
            if name then
                if name:lower() == exe_name:lower() then
                    table.insert(pids, tonumber(entry.th32ProcessID))
                end
            end
            ok = C.Process32NextW(snap, entry)
        end
        return pids
    end)
    C.CloseHandle(snap) -- Always cleanup handle
    if not success then
        logger:error("Error during process enumeration: " .. tostring(result))
        return {}
    end
    return result
end

local function EnableBlurBehind(hwnd)
    local policy = ffi.new("ACCENTPOLICY")
    policy.nAccentState = 4
    policy.nFlags = ACCENT_FLAG_ENABLE_BLURBEHIND
    policy.nColor = 0x00000000
    policy.nAnimationId = 0

    local data = ffi.new("WINDOWCOMPOSITIONATTRIBDATA")
    data.nAttribute = WCA_ACCENT_POLICY
    data.pData = ffi.cast("void*", ffi.cast("ACCENTPOLICY*", policy))
    data.ulDataSize = ffi.sizeof(policy)

    local ok
    local s, fn = pcall(function() return user32.SetWindowCompositionAttribute end)
    if s and fn ~= nil then
        ok = fn(hwnd, data)
    else
        ok = C.SetWindowCompositionAttribute(hwnd, data)
    end
    return ok ~= 0
end

local function EnableRoundedCorners(hwnd)
    local pref = ffi.new("int[1]", DWMWCP_ROUND)
    local hr = dwmapi.DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, pref, ffi.sizeof(pref))
    return hr == 0
end

local function PatchWindowContext(hwnd)
    if IS_CORNER_PREFERENCE_COMPATIBLE then
        local ok = EnableRoundedCorners(hwnd)
        if not ok then logger:error("EnableRoundedCorners failed") end
    end
    if IS_BLUR_BEHIND_COMPATIBLE then
        local ok = EnableBlurBehind(hwnd)
        if not ok then logger:error("EnableBlurBehind failed") end
    end
end

local function init_window_enum_callback()
    if window_enum_callback then return end

    window_enum_callback = ffi.cast("WNDENUMPROC", function(hwnd, lParam)
        local out = ffi.new("DWORD[1]")
        C.GetWindowThreadProcessId(hwnd, out)
        local window_pid = tonumber(out[0])
        for _, target_pid in ipairs(current_target_pids) do
            if window_pid == target_pid then
                local ok, err = pcall(PatchWindowContext, hwnd)
                if not ok then
                    logger:error(string.format("[PatchAllWindows] Failed to patch hwnd=%s, error: %s", tostring(hwnd), tostring(err)))
                end
                break
            end
        end
        return 1 
    end)
end

function PatchAllWindows()
    init_window_enum_callback() 
    local targets = find_pids_by_name("steamwebhelper.exe")
    if #targets == 0 then
        logger:info("[PatchAllWindows] No steamwebhelper.exe processes found.")
        return false
    end
    current_target_pids = targets
    local ok_enum, err = pcall(function()
        C.EnumWindows(window_enum_callback, 0)
    end)
    if not ok_enum then
        logger:error(string.format("[PatchAllWindows] Failed to enumerate windows, error: %s", tostring(err)))
        return false
    end
    return true
end

local function on_load()
    print("Example plugin loaded")
    logger:info("Example plugin loaded with Millennium version " .. millennium.version())
    millennium.ready()
end

local function on_unload()
    logger:info("Plugin unloaded")
    -- Clean up callback if needed (though FFI callbacks are GC'd automatically)
    window_enum_callback = nil
    current_target_pids = {}
end

local function on_frontend_loaded()
    logger:info("Frontend loaded")
    local result = millennium.call_frontend_method("classname.method", { 18, "USA", false })
    logger:info(result)
end

return {
    on_frontend_loaded = on_frontend_loaded,
    on_load = on_load,
    on_unload = on_unload
}