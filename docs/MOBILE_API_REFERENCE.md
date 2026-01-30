# Guardian AI - Comprehensive Mobile API Reference

This document provides a consolidated reference for all API endpoints and WebSocket channels utilized by the Guardian AI mobile application.

## 1. Connection Settings
- **Base URL:** `https://seraphguardlabs.com`
- **WebSocket Base:** `wss://seraphguardlabs.com`

---

## 2. Authentication

### Parent Signup
- **Endpoint:** `POST /api/accounts/signup/`
- **Body:**
  ```json
  {
    "full_name": "Full Name",
    "email": "user@example.com",
    "password": "securepassword"
  }
  ```

### Parent Login
- **Endpoint:** `POST /api/accounts/login/`
- **Body:**
  ```json
  {
    "email": "user@example.com",
    "password": "securepassword"
  }
  ```

---

## 3. Child Management

### Add a Child
- **Endpoint:** `POST /api/mobile/parent/add-child/`
- **Headers:** `X-Email`, `X-Password`
- **Body:**
  ```json
  {
    "first_name": "John",
    "last_name": "Doe",
    "date_of_birth": "2015-05-15"
  }
  ```

### List Linked Children
- **Endpoint:** `GET /api/mobile/parent/children/`
- **Headers:** `X-Email`, `X-Password`

---

## 4. Real-time Data Ingestion

The child device sends telemetry via WebSocket with HTTP as a fallback.

### WebSocket Ingest Channel
- **URL:** `wss://seraphguardlabs.com/ws/ingest/<child_hash>/`
- **Event Types:**
  - `location`: Send latitude/longitude.
  - `screen_time`: Send daily usage stats per app.
  - `site_access`: Send browser history logs.
  - `ai_alert`: Send threat detection alerts.

### HTTP Ingest Fallback
- **Endpoint:** `POST /api/ingest/`
- **Headers:** `X-Child-Hash`
- **Body Template:**
  ```json
  {
    "child_hash": "...",
    "data_type": "location",
    "payload": {
      "timestamp": "ISO-8601-STRING",
      "latitude": 40.7128,
      "longitude": -74.0060
    }
  }
  ```

---

## 5. Parental Controls & Restrictions

### Daily Screen Time Limit
- **Fetch:** `GET /api/mobile/child/<child_hash>/daily-limit/`
- **Update:** `POST /api/mobile/child/<child_hash>/daily-limit/`
- **Headers:** `X-Email`, `X-Password`
- **Body:** `{"daily_screen_time_limit": 2.5}`

### Exam Mode (Focus Mode)
- **Fetch:** `GET /api/mobile/child/<child_hash>/exam-mode/`
- **Update:** `POST /api/mobile/child/<child_hash>/exam-mode/`
- **Body:** `{"exam_mode": true, "exam_mode_apps": ["com.social.app"]}`

### App Blocking (Per-App)
- **Fetch:** `GET /api/mobile/child/<child_hash>/restricted-apps/`
- **Update:** `POST /api/mobile/child/<child_hash>/restricted-apps/`
- **Action:** `add`, `remove`, `update`

---

## 6. Task Management

### Create Task (Guardian)
- **Endpoint:** `POST /api/mobile/child/<child_hash>/tasks/`
- **Headers:** `X-Email`, `X-Password`
- **Body:**
  ```json
  {
    "title": "Clean your room",
    "description": "Pick up toys and organize the desk",
    "due_date": "2026-02-01T12:00:00Z"
  }
  ```

### View Tasks (Child View)
- **Endpoint:** `GET /api/mobile/child/<child_hash>/my-tasks/?completed=false`
- **Headers:** `X-Child-Hash`

---

## 7. Security (Encryption)

### Public Key Management
- **Upload:** `POST /api/mobile/child/public-key/upload/`
- **Fetch:** `GET /api/mobile/child/<child_hash>/public-key/`
- **Purpose:** Used to encrypt task descriptions and chat messages locally.

---

## 8. AI Alerts & Safety

### Fetch Alerts (Guardian)
- **Endpoint:** `GET /api/mobile/child/<child_hash>/alerts/`
- **Headers:** `X-Email`, `X-Password`

### Acknowledge Alert (Guardian)
- **Endpoint:** `POST /api/mobile/child/<child_hash>/alerts/<alert_id>/acknowledge/`
