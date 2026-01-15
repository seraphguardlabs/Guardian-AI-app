import ctypes
from ctypes import wintypes

class WindowMonitor:
    """
    Layer 1: Acquisition
    Captures the title of the currently active window to track App Usage.
    """
    def __init__(self):
        self.user32 = ctypes.windll.user32
        print("Window Monitor initialized.")

    def get_active_window(self):
        """
        Returns the title of the active window (e.g., "YouTube - Google Chrome").
        """
        try:
            hWnd = self.user32.GetForegroundWindow()
            length = self.user32.GetWindowTextLengthW(hWnd)
            buf = ctypes.create_unicode_buffer(length + 1)
            self.user32.GetWindowTextW(hWnd, buf, length + 1)
            title = buf.value
            if title:
                return title
            return "Unknown App"
        except Exception:
            return "Unknown"
