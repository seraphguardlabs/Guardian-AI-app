import time
import random
import threading
from guardian_ai.utils.database import DatabaseManager
from guardian_ai.dashboard.app import run_dashboard

# Layer 1: Acquisition
from guardian_ai.acquisition import NetworkMonitor, ScreenSampler, TextExtractor, MediaInspector, WindowMonitor

# Layer 2: Analysis
from guardian_ai.analysis import ImageAnalyzer, TextAnalyzer, BehaviorTracker, ThreatMatcher

# Layer 3: Decision
from guardian_ai.decision import RiskScorer, ActionEngine, AlertGenerator, Transmitter

# Utils
from guardian_ai.utils import EvidenceLogger

def main():
    print("=== Guardian-AI Parental Threat Detection System Starting ===")
    
    # --- Initialization ---
    print("\n[INIT] Initializing modules...")
    
    # Layer 1
    net_mon = NetworkMonitor()
    screen_cap = ScreenSampler()
    text_ext = TextExtractor()
    media_insp = MediaInspector()
    win_mon = WindowMonitor()
    
    # Layer 2
    img_ana = ImageAnalyzer()
    text_ana = TextAnalyzer()
    beh_track = BehaviorTracker()
    threat_match = ThreatMatcher()
    
    # Layer 3
    risk_scorer = RiskScorer()
    action_engine = ActionEngine()
    alert_gen = AlertGenerator()
    transmitter = Transmitter()
    logger = EvidenceLogger()
    db = DatabaseManager()
    
    # --- Start Dashboard ---
    dash_thread = threading.Thread(target=run_dashboard, args=(5000,), daemon=True)
    dash_thread.start()
    print("[INIT] Dashboard running at http://localhost:5000")
    
    print("[INIT] System Ready. Starting Monitoring Loop... (Press Ctrl+C to Stop)\n")
    
    cycle_count = 0
    
    # --- Monitoring Loop (Continuous) ---
    try:
        while True:
            cycle_count += 1
            print(f"--- Cycle {cycle_count} ---")
            
            # 1. ACQUISITION
            print(">> Layer 1: Acquisition")
            frame = screen_cap.capture_frame()
            
            # Text (OCR)
            current_text = ""
            current_app = win_mon.get_active_window()
            
            if frame:
                try:
                    current_text = text_ext.extract_from_image(frame)
                    if len(current_text) > 10:
                        print(f"   [OCR] Extracted: {current_text[:60]}...")
                except Exception as e:
                    print(f"   [OCR] Error: {e}")

            # Network (Placeholder for real DPI)
            packet = {"domain": "safe-site.com"} 
            is_net_safe = net_mon.scan_packet(packet)
            
            # 2. ANALYSIS
            # print(">> Layer 2: Analysis")
            # Image
            img_res = img_ana.analyze_frame(frame)
            
            # Text
            text_res = text_ana.analyze_text(current_text)
            
            # Behavior
            beh_track.add_event("active", time.time())
            beh_score = beh_track.analyze_pattern()
            
            # 3. DECISION & RESPONSE
            print(">> Layer 3: Decision")
            
            # Calculate Risk
            # High network risk if packet filtered
            net_risk = 0.0 if is_net_safe else 1.0 
            
            total_risk = risk_scorer.calculate_risk(
                image_risk=img_res.get("risk_score", 0.0),
                text_risk=text_res.get("risk_score", 0.0),
                behavior_risk=beh_score,
                metadata_risk=net_risk # prioritizing network block as metadata risk for this demo
            )
            print(f"   [Scoring] Image: {img_res.get('risk_score', 0.0):.2f} | Text: {text_res.get('risk_score', 0.0):.2f} | Behavior: {beh_score:.2f}")
            print(f"   [Decision] Total Risk: {total_risk:.2f} (Max Strategy)")
            
            # Take Action
            action = action_engine.take_action(total_risk, f"Cycle-{cycle_count}")
            
            # Evidence Saving
            # Evidence Saving (Disk)
            screenshot_path = ""
            if total_risk > 0.5:
                # Save Screenshot
                if img_res["risk_score"] > 0.0:
                     saved_path = logger.save_screenshot(frame, total_risk, source="screen")
                     if saved_path:
                         screenshot_path = saved_path
                
                # Log Text
                if text_res["risk_score"] > 0.0:
                     logger.log_text_incident(current_text, text_res["risk_score"], text_res["labels"])

            # Alert if needed
            labels = img_res.get("labels", []) + text_res.get("labels", [])
            alert = alert_gen.generate_alert(total_risk, labels, f"Cycle-{cycle_count}")
            
            if alert:
                print(f"   [Alert] {alert}")
                transmitter.send_alert({"alert": alert, "timestamp": time.time()})
            
            # Periodic Reporting
            if cycle_count % 10 == 0:
                print(">> Generating Daily Report...")
                beh_track.generate_report()
                
             # Log to Database (For Dashboard)
            cycle_data = {
                "timestamp": time.time(),
                "image_risk": img_res.get("risk_score", 0.0),
                "text_risk": text_res.get("risk_score", 0.0),
                "behavior_risk": beh_score,
                "total_risk": total_risk,
                "extracted_text": current_text,
                "ocr_labels": text_res.get("labels", []),
                "vision_labels": img_res.get("labels", []),
                "screenshot_path": screenshot_path,
                "app_name": current_app
            }
            db.log_cycle(cycle_data)

            # print(f"--- End Cycle {cycle_count} ---\n")
            time.sleep(2) # 2-second interval
            
    except KeyboardInterrupt:
        print("Monitoring stoped.")
        
    print("=== Guardian-AI System Shutdown ===")

if __name__ == "__main__":
    main()
