class RiskScorer:
    """
    Layer 3: Risk Scoring
    Aggregates signals from Layer 2 (Analysis) into a single risk score (0.0 - 1.0).
    """

    def __init__(self):
        print("Initializing RiskScorer (Weighted Aggregation)...")
        # Weights for different signal types
        self.weights = {
            "image": 0.4,
            "text": 0.4,
            "behavior": 0.1,
            "metadata": 0.1
        }

    def calculate_risk(self, image_risk=0.0, text_risk=0.0, behavior_risk=0.0, metadata_risk=0.0):
        """
        Combines separate risk scores.
        
        Args:
           image_risk (float): 0.0-1.0
           text_risk (float): 0.0-1.0
           behavior_risk (float): 0.0-1.0
           metadata_risk (float): 0.0-1.0
           
        Returns:
            float: Combined risk score.
        """
        if image_risk > 0.85 or text_risk > 0.85:
            # CRITICAL VETO: If any single detector is very sure, override the average.
            # This ensures that "Nudity: 0.96" results in "Risk: 1.0" even if text is safe.
            return 1.0

        # INDEPENDENT SCORING STRATEGY
        # The user requested that we do not mix/compare these. 
        # If Image is bad, it's bad. If Text is bad, it's bad.
        # We take the MAXIMUM risk found in any category.
        
        score = max(image_risk, text_risk, behavior_risk, metadata_risk)
        
        return score
