class ActionEngine:
    """
    Layer 3: Action Engine
    Executes protective actions based on risk score.
    """

    def __init__(self):
        print("Initializing ActionEngine (Block/Pause/Blur)...")
        self.active_blocks = set()

    def take_action(self, risk_score, source_id):
        """
        Determines and executes action.
        
        Args:
            risk_score (float): Current aggregated risk.
            source_id (str): ID of the app or content source.
            
        Returns:
            str: Description of action taken.
        """
        if risk_score > 0.8:
            action = f"BLOCK_ACCESS: {source_id}"
            self.active_blocks.add(source_id)
            print(f"!!! ACTION TRIGGERED: {action} !!!")
            return action
        elif risk_score > 0.5:
            action = f"WARN_USER: {source_id}"
            print(f"!!! ACTION TRIGGERED: {action} !!!")
            return action
        else:
            return "NO_ACTION"
