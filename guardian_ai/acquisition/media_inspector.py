import os
import time

class MediaInspector:
    """
    Layer 1: Media Inspection
    Scans new files for suspicious metadata.
    """

    def __init__(self):
        print("Initializing MediaInspector (File scanner)...")

    def scan_file_metadata(self, file_path):
        """
        Checks file stats.
        
        Returns:
            dict: Metadata including timestamp and size.
        """
        if not os.path.exists(file_path):
            return {"error": "File not found"}
            
        stats = os.stat(file_path)
        return {
            "size": stats.st_size,
            "created": time.ctime(stats.st_ctime),
            "modified": time.ctime(stats.st_mtime)
        }
