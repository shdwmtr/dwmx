import Millennium
import win32con
import ctypes
import sys
import time
import ctypes.wintypes
import win32process
from utils.user32 import get_proc_name
from utils.set_attr import patch_window

WINEVENT_OUTOFCONTEXT = 0x0000

user32 = ctypes.windll.user32
ole32 = ctypes.windll.ole32
ole32.CoInitialize(0)

WinEventProcType = ctypes.WINFUNCTYPE(
    None, 
    ctypes.wintypes.HANDLE,
    ctypes.wintypes.DWORD,
    ctypes.wintypes.HWND,
    ctypes.wintypes.LONG,
    ctypes.wintypes.LONG,
    ctypes.wintypes.DWORD,
    ctypes.wintypes.DWORD
)

def callback(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime):

    print("callback was called")

    tid, pid = win32process.GetWindowThreadProcessId(hwnd)
    process_name = get_proc_name(pid)

    if process_name == "steamwebhelper.exe":
        print("patchin steam window")
        patch_window(hwnd)


class Plugin:

    # if steam reloads, i.e. from a new theme being selected, or for other reasons, this is called. 
    # with the above said, that means this may be called more than once within your backends lifespan 
    def _front_end_loaded(self):
        pass


    def _load(self):     
        print("loading mica effects")
        WinEventProc = WinEventProcType(callback)

        user32.SetWinEventHook.restype = ctypes.wintypes.HANDLE
        self.__hook = user32.SetWinEventHook(win32con.EVENT_OBJECT_CREATE, win32con.EVENT_OBJECT_SHOW, 0, WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT)

        if self.__hook == 0:
            sys.stderr.write('SetWinEventHook failed')
            self._unload()
        else:
            print("set window create hook")

        self.__listen = True
        # Set up the event hook
        # Enter a message loop to keep the hook running asynchronously.
        # This ensures that the system can process messages and events while the hook remains active.
        msg = ctypes.wintypes.MSG()
        while self.__listen and user32.GetMessageW(ctypes.byref(msg), 0, 0, 0) != 0:
            print("listening for message")
            user32.TranslateMessageW(msg)
            user32.DispatchMessageW(msg)

        print("closed message listener")

    def _unload(self):
        print("unloading")
        user32.UnhookWinEvent(self.__hook)
        ole32.CoUninitialize()
        self.__listen = False


# plugin = Plugin()
# plugin._load()