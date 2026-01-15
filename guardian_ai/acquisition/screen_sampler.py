import platform

try:
    from PIL import ImageGrab, Image
except ImportError:
    ImageGrab = None
    Image = None

class ScreenSampler:
    """
    Layer 1: Screen Sampling
    Captures screenshots at a low frame rate (1-2 FPS).
    """

    def __init__(self):
        print(f"Initializing ScreenSampler (Platform: {platform.system()})...")

    def capture_frame(self):
        """
        Captures the current screen content.
        
        Returns:
            PIL.Image or None: The captured frame.
        """
        if ImageGrab:
            try:
                # Capture the primary monitor
                return ImageGrab.grab()
            except Exception as e:
                print(f"Capture failed: {e}")
                return None
        return None
