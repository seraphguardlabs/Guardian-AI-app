import numpy as np

try:
    import easyocr
    OCR_AVAILABLE = True
except ImportError:
    OCR_AVAILABLE = False

class TextExtractor:
    """
    Layer 1: Text Extraction
    Uses EasyOCR to scrape text directly from screenshots.
    """

    def __init__(self):
        self._reader_ready = False
        if OCR_AVAILABLE:
            try:
                print("Initializing TextExtractor (EasyOCR)...")
                # Detect english text. gpu=False if no CUDA, but try true if available
                self.reader = easyocr.Reader(['en'], gpu=True) 
                self._reader_ready = True
                print("OCR Engine Ready.")
            except Exception as e:
                print(f"Failed to init EasyOCR: {e}")
                # Fallback to CPU if GPU failed (common on non-nvidia machines)
                try:
                    self.reader = easyocr.Reader(['en'], gpu=False)
                    self._reader_ready = True
                    print("OCR Engine Ready (CPU Mode).")
                except:
                    pass
        else:
             print("EasyOCR not found. Text extraction disabled.")

    def extract_from_image(self, image):
        """
        Extracts text from a PIL Image.
        """
        if not self._reader_ready or image is None:
            return ""

        try:
            # EasyOCR expects numpy array or file path
            img_np = np.array(image)
            
            # detail=0 returns just the headers/paragraphs list
            result_list = self.reader.readtext(img_np, detail=0)
            
            full_text = " ".join(result_list)
            return full_text
            
        except Exception as e:
            print(f"OCR Failed: {e}")
            return ""

    def get_current_text(self):
         # Legacy method, replaced by extract_from_image
         return ""
