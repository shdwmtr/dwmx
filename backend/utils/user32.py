import psutil

def GetProcessName(pid):
    try:
        return psutil.Process(pid).name()
    except psutil.NoSuchProcess:
        return None