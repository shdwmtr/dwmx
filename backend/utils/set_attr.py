import ctypes
from ctypes import wintypes

DWMWA_WINDOW_CORNER_PREFERENCE = 33
ACCENT_ENABLE_BLURBEHIND = 3
ACCENT_FLAG_ENABLE_BLURBEHIND = 0x20
WCA_ACCENT_POLICY = 19

class ACCENTPOLICY(ctypes.Structure):
    _fields_ = [("nAccentState", ctypes.c_int), ("nFlags", ctypes.c_int), ("nColor", ctypes.c_uint), ("nAnimationId", ctypes.c_int)]

class WINDOWCOMPOSITIONATTRIBDATA(ctypes.Structure):
    _fields_ = [("nAttribute", ctypes.c_uint), ("pData", ctypes.c_void_p), ("ulDataSize", ctypes.c_size_t)]

user32 = ctypes.WinDLL("user32.dll")

SetWindowCompositionAttribute = user32.SetWindowCompositionAttribute
SetWindowCompositionAttribute.argtypes = [wintypes.HWND, ctypes.POINTER(WINDOWCOMPOSITIONATTRIBDATA)]
SetWindowCompositionAttribute.restype = wintypes.BOOL

def EnableBlurBehind(target):

    policy = ACCENTPOLICY()
    policy.nAccentState = ACCENT_ENABLE_BLURBEHIND
    policy.nFlags = ACCENT_FLAG_ENABLE_BLURBEHIND
    policy.nColor = 0x00000000
    policy.nAnimationId = 0

    data = WINDOWCOMPOSITIONATTRIBDATA()
    data.nAttribute = WCA_ACCENT_POLICY
    data.pData = ctypes.cast(ctypes.pointer(policy), ctypes.c_void_p)
    data.ulDataSize = ctypes.sizeof(policy)

    return SetWindowCompositionAttribute(target, ctypes.byref(data))

def EnableRoundedCorners(target):
    value = ctypes.c_int(2)
    ctypes.windll.dwmapi.DwmSetWindowAttribute(target, DWMWA_WINDOW_CORNER_PREFERENCE, ctypes.byref(value), ctypes.sizeof(value))

def PatchWindowContext(hwnd):
    
    EnableRoundedCorners(hwnd)
    EnableBlurBehind(hwnd)