class NetworkMonitor:
    """
    Layer 1: Network Monitoring
    Simulates Deep Packet Inspection (DPI) to check packet headers.
    """
    
    def __init__(self):
        print("Initializing NetworkMonitor (DPI simulation)...")
        # In a real app, this would bind to VpnService
        self.blocked_domains = {"bad-site.com", "malware.net"}

    def scan_packet(self, packet_header):
        """
        Checks a packet header for restricted domains.
        
        Args:
            packet_header (dict): Simulated header data (e.g., {"domain": "google.com"})
            
        Returns:
            bool: True if safe, False if blocked.
        """
        domain = packet_header.get("domain", "")
        if domain in self.blocked_domains:
            return False
        return True
