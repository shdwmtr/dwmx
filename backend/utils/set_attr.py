import ctypes
from ctypes import wintypes

DWMWA_WINDOW_CORNER_PREFERENCE = 33

# Define the ACCENTPOLICY structure
class ACCENTPOLICY(ctypes.Structure):
    _fields_ = [
        ("nAccentState", ctypes.c_int),
        ("nFlags", ctypes.c_int),
        ("nColor", ctypes.c_uint),
        ("nAnimationId", ctypes.c_int)
    ]

# Define the WINDOWCOMPOSITIONATTRIBDATA structure
class WINDOWCOMPOSITIONATTRIBDATA(ctypes.Structure):
    _fields_ = [
        ("nAttribute", ctypes.c_uint),
        ("pData", ctypes.POINTER(ACCENTPOLICY)),
        ("ulDataSize", ctypes.c_size_t)
    ]

# Load user32.dll library
user32 = ctypes.WinDLL("user32.dll")

# Define function prototype for SetWindowCompositionAttribute
SetWindowCompositionAttribute = user32.SetWindowCompositionAttribute
SetWindowCompositionAttribute.argtypes = [wintypes.HWND, ctypes.POINTER(WINDOWCOMPOSITIONATTRIBDATA)]
SetWindowCompositionAttribute.restype = wintypes.BOOL

# Define constants
ACCENT_ENABLE_BLURBEHIND = 3
ACCENT_FLAG_ENABLE_BLURBEHIND = 0x20
WCA_ACCENT_POLICY = 19

def EnableBlurBehind(target):
    # Define the ACCENTPOLICY structure with blur effect settings
    policy = ACCENTPOLICY()
    policy.nAccentState = ACCENT_ENABLE_BLURBEHIND
    policy.nFlags = ACCENT_FLAG_ENABLE_BLURBEHIND
    policy.nColor = 0x00000000
    policy.nAnimationId = 0

    # Set the WINDOWCOMPOSITIONATTRIBDATA data
    data = WINDOWCOMPOSITIONATTRIBDATA()
    data.nAttribute = WCA_ACCENT_POLICY
    data.pData = ctypes.pointer(policy)
    data.ulDataSize = ctypes.sizeof(policy)

    # Call SetWindowCompositionAttribute to enable blur effect
    result = SetWindowCompositionAttribute(target, ctypes.byref(data))

    if not result:
        #print("SetWindowCompositionAttribute failed")
        return False

    return True

dwmapi = ctypes.windll.dwmapi
DwmSetWindowAttribute = dwmapi.DwmSetWindowAttribute

# Call DwmSetWindowAttribute function
def patch_window(hwnd):
    value = ctypes.c_int(2)
    DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, ctypes.byref(value), ctypes.sizeof(value))
    EnableBlurBehind(hwnd)
