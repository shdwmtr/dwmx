local logger = require("logger")
local millennium = require("millennium")
local ffi = require("ffi")

-- CHANGE: unsigned long is 32-bit on Windows x64 (LLP64); uintptr_t/intptr_t
-- correctly resolves to 64-bit, matching the actual PROCESSENTRY32W struct layout.
-- Using the wrong width causes the struct fields after th32DefaultHeapID to be
-- misaligned, which leads to reading garbage PIDs and eventual access violations.
ffi.cdef[[
typedef int BOOL;
typedef unsigned long DWORD;
typedef long LONG;
typedef unsigned long ULONG;
typedef void* HANDLE;
typedef void* HWND;
typedef wchar_t WCHAR;
typedef uintptr_t ULONG_PTR;
typedef intptr_t LONG_PTR;
typedef LONG_PTR LPARAM;
typedef unsigned int UINT;
typedef long HRESULT;
typedef int INT;
typedef unsigned long SIZE_T;
typedef char CHAR;
typedef CHAR* LPSTR;

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
local WCA_ACCENT_POLICY_VAL = 19
local ACCENT_ENABLE_HOSTBACKDROP = 4
local ACCENT_FLAG_ENABLE_BLURBEHIND = 0x20
local DWMWA_WINDOW_CORNER_PREFERENCE = 33
local DWMWCP_ROUND = 2

-- CHANGE: cast through intptr_t so the sentinel is sign-extended to 64-bit
-- (0xFFFFFFFFFFFFFFFF), matching INVALID_HANDLE_VALUE on x64. A bare cast of
-- -1 to void* is not guaranteed to produce the correct pointer value.
local INVALID_HANDLE_VALUE = ffi.cast("HANDLE", ffi.cast("intptr_t", -1))

-- CHANGE: pre-allocate the PID output buffer used inside the enum callback.
-- Allocating with ffi.new() inside an FFI callback on every window invocation
-- hammers the GC while executing from C, which is a stability hazard.
-- Extended to all buffers used in the hot path for the same reason.
local g_pid_buf = ffi.new("DWORD[1]")
local g_name_buf = ffi.new("char[260]")
local g_proc_entry = ffi.new("PROCESSENTRY32W")
local g_accent_policy = ffi.new("ACCENTPOLICY")
local g_corner_pref = ffi.new("int[1]", DWMWCP_ROUND)
local g_composition_data = ffi.new("WINDOWCOMPOSITIONATTRIBDATA")

-- Wire up pData once; pointer stays valid for the plugin lifetime.
g_composition_data.nAttribute = WCA_ACCENT_POLICY_VAL
g_composition_data.pData = ffi.cast("void*", g_accent_policy)
g_composition_data.ulDataSize = ffi.sizeof("ACCENTPOLICY")

-- Single reusable callback - created once and reused
local window_enum_callback = nil

-- Feature flags (populated in on_load)
local IS_BLUR_BEHIND_COMPATIBLE = false
local IS_CORNER_PREFERENCE_COMPATIBLE = false

-- Global state for window enumeration
local current_target_pids = {}

-- cast wchar to utf8 string.
-- 260 == MAX_PATH, we assume steam is not running from a path longer than that.
-- that is likely a safe assumption (I hope).
local function wchar_to_utf8(wstr)
    local n = C.WideCharToMultiByte(CP_UTF8, 0, wstr, -1, g_name_buf, 260, nil, nil)
    return n > 0 and ffi.string(g_name_buf) or nil
end

-- find all process IDs matching the given executable name (case insensitive)
local function find_pids_by_name(exe_name)
    local snap = C.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if snap == INVALID_HANDLE_VALUE then
        logger:error("CreateToolhelp32Snapshot failed")
        return {}
    end

    g_proc_entry.dwSize = ffi.sizeof("PROCESSENTRY32W")
    local exe_lower = exe_name:lower()

    local ok, result = pcall(function()
        local out = {}
        if C.Process32FirstW(snap, g_proc_entry) ~= 0 then
            repeat
                local name = wchar_to_utf8(g_proc_entry.szExeFile)
                if name and name:lower() == exe_lower then
                    table.insert(out, tonumber(g_proc_entry.th32ProcessID))
                end
            until C.Process32NextW(snap, g_proc_entry) == 0
        end
        return out
    end)

    C.CloseHandle(snap) -- Always cleanup handle

    if not ok then
        logger:error("Error during process enumeration: " .. tostring(result))
        return {}
    end
    return result
end

local function EnableBlurBehind(hwnd)
    g_accent_policy.nAccentState = ACCENT_ENABLE_HOSTBACKDROP
    g_accent_policy.nFlags = ACCENT_FLAG_ENABLE_BLURBEHIND
    g_accent_policy.nColor = 0x00000000
    g_accent_policy.nAnimationId = 0
    -- CHANGE: removed the pcall/fallback that called C.SetWindowCompositionAttribute.
    -- ffi.C resolves to the CRT (msvcrt/ucrtbase), not user32 — calling a user32
    -- symbol through it produces a bad function pointer and causes an access violation.
    -- SetWindowCompositionAttribute belongs to user32, so call it directly from there.
    return user32.SetWindowCompositionAttribute(hwnd, g_composition_data) ~= 0
end

local function EnableRoundedCorners(hwnd)
    local hr = dwmapi.DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, g_corner_pref, ffi.sizeof(g_corner_pref))
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

    window_enum_callback = ffi.cast("WNDENUMPROC", function(hwnd, _lParam)
        -- CHANGE: use the pre-allocated g_pid_buf instead of ffi.new("DWORD[1]") here.
        C.GetWindowThreadProcessId(hwnd, g_pid_buf)
        local window_pid = tonumber(g_pid_buf[0])
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
    local ok, err = pcall(C.EnumWindows, window_enum_callback, 0)
    if not ok then
        logger:error(string.format("[PatchAllWindows] Failed to enumerate windows, error: %s", tostring(err)))
        return false
    end
    return true
end

local function on_load()
    -- CHANGE: probe feature availability at runtime instead of hardcoding true.
    -- SetWindowCompositionAttribute is Win8+. DWMWA_WINDOW_CORNER_PREFERENCE (attr 33)
    -- is Win11+ and can't be probed without a real HWND, so we enable it and let
    -- per-call errors surface naturally.
    local blur_ok = pcall(function() return user32.SetWindowCompositionAttribute end)
    IS_BLUR_BEHIND_COMPATIBLE = blur_ok
    IS_CORNER_PREFERENCE_COMPATIBLE = true

    logger:info(string.format(
        "Plugin loaded (Millennium %s) — blur=%s rounded_corners=%s",
        millennium.version(),
        tostring(IS_BLUR_BEHIND_COMPATIBLE),
        tostring(IS_CORNER_PREFERENCE_COMPATIBLE)))

    millennium.ready()
end

local function on_unload()
    logger:info("Plugin unloaded")
    -- CHANGE: explicitly free the FFI trampoline before clearing the reference.
    -- Without :free(), unloading and reloading the plugin leaks the native stub.
    if window_enum_callback then
        window_enum_callback:free()
    end
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
