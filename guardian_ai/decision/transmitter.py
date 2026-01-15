import json

class Transmitter:
    """
    Layer 3: Secure Transmitter
    Encrypts and sends alerts to the dashboard.
    """

    def __init__(self):
        print("Initializing Transmitter (Secure Channel)...")

    def send_alert(self, alert_data):
        """
        Transmits the alert.
        
        Args:
            alert_data (dict): The alert payload.
            
        Returns:
            bool: Success status.
        """
        # Simulate encryption and network send
        payload = json.dumps(alert_data)
        encrypted = f"ENC[{payload}]" # Mock encryption
        
        print(f"Server <-- {encrypted}")
        return True
