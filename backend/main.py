import threading
import win32con
import ctypes
import sys
import ctypes.wintypes
import win32process
from utils.logger import logger
from utils.user32 import GetProcessName
from utils.set_attr import PatchWindowContext
import Millennium

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

    if event == 32770:
        return

    _, pid = win32process.GetWindowThreadProcessId(hwnd)
    process_name = GetProcessName(pid)

    if process_name == "steamwebhelper.exe":
        PatchWindowContext(hwnd)


class Plugin:

    def _front_end_loaded(self):
        pass

    def start_dwmx(self):
        WinEventProc = WinEventProcType(callback)

        user32.SetWinEventHook.restype = ctypes.wintypes.HANDLE
        self.__hook = user32.SetWinEventHook(win32con.EVENT_OBJECT_CREATE, win32con.EVENT_OBJECT_SHOW, 0, WinEventProc, 0, 0, WINEVENT_OUTOFCONTEXT)

        if self.__hook == 0:
            logger.error('SetWinEventHook failed')
            self._unload()
        else:
            logger.log("set window create hook")

        msg = ctypes.wintypes.MSG()
        while self.__listen:
            while user32.PeekMessageW(ctypes.byref(msg), 0, 0, 0, win32con.PM_REMOVE):
                user32.TranslateMessageW(msg)
                user32.DispatchMessageW(msg)

        logger.log("closed message listener")

    def _load(self):     
        logger.log("warming dwmx...")
        self.__listen = True
        self.dwmx_thread = threading.Thread(target=self.start_dwmx)
        self.dwmx_thread.start()
        Millennium.ready()

    def _unload(self):
        logger.log("unloading dwmx...")
        self.__listen = False
        self.dwmx_thread.join()
        user32.UnhookWinEvent(self.__hook)
        ole32.CoUninitialize()
