# Gamified Permission System API Endpoints

This document describes the structure, headers, JSON formats, and file locations for the new endpoints implemented in the GuardianAI-backend project.

---

## 1. Get Suggested Reward Tasks

- **Method:** GET  
- **URL:** `/api/mobile/time-extension-requests/suggested-tasks/`
- **Headers:**  
  - `X-Email`: guardian email  
  - `X-Password`: guardian password
- **Body:** _None_
- **Sample Response:**
  ```json
  {
    "status": "ok",
    "suggested_tasks": [
      {"id": "play_chess", "title": "Play Chess", "description": "Engage in a game of chess"},
      {"id": "exercise", "title": "Exercise for 20 mins", "description": "Do some light stretching or cardio"},
      {"id": "read", "title": "Read Newspaper", "description": "Read at least three major articles"}
    ]
  }
  ```
- **File Location:**  
  - URL pattern: `messaging/urls.py`  
  - View logic: `messaging/views.py` (`api_suggested_reward_tasks`)

---

## 2. Assign Reward Task to Request

- **Method:** POST  
- **URL:** `/api/mobile/time-extension-requests/{request_id}/assign-task/`
- **Headers:**  
  - `X-Email`: guardian email  
  - `X-Password`: guardian password
- **Body (suggested):**
  ```json
  {
    "suggestion_id": "play_chess",
    "is_custom": false
  }
  ```
- **Body (custom):**
  ```json
  {
    "is_custom": true,
    "task_title": "Custom Task",
    "task_description": "Custom Description"
  }
  ```
- **Sample Response:**
  ```json
  {
    "status": "ok",
    "message": "Task assigned (stub)"
  }
  ```
- **File Location:**  
  - URL pattern: `messaging/urls.py`  
  - View logic: `messaging/views.py` (`api_assign_reward_task`)

---

## 3. Approve Time Extension Request

- **Method:** POST  
- **URL:** `/api/mobile/time-extension-requests/{request_id}/approve/`
- **Headers:**  
  - `X-Email`: guardian email  
  - `X-Password`: guardian password
- **Body:**
  ```json
  {
    "granted_hours": 1.5
  }
  ```
- **Sample Response:**
  ```json
  {
    "status": "ok",
    "message": "Time extension approved (stub)"
  }
  ```
- **File Location:**  
  - URL pattern: `messaging/urls.py`  
  - View logic: `messaging/views.py` (`api_approve_time_extension`)

---

## 4. Mark Task as Complete (Child)

- **Method:** POST  
- **URL:** `/api/mobile/child/{child_hash}/tasks/{task_id}/complete/`
- **Headers:**  
  - `X-Child-Hash`: child hash
- **Body:** _None_
- **Sample Response:**
  ```json
  {
    "status": "ok",
    "message": "Task marked as completed",
    "task": {
      "id": 123,
      "title": "Play Chess",
      "description": "Engage in a game of chess",
      "is_completed": true,
      "completed_at": "2026-01-30T12:34:56.789Z"
    }
  }
  ```
- **File Location:**  
  - URL pattern: `messaging/urls.py`  
  - View logic: `messaging/views.py` (`api_child_mark_task_complete`)

---

Replace placeholders with real values as needed.
