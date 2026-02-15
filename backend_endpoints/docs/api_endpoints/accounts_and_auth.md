# 10. Add Child (Mobile)
- **URL:** `/accounts/api/mobile/children/add/`
- **Method:** `POST`
- **Auth:** X-Auth-Email and X-Auth-Password headers
- **Description:** Add a new child under a logged-in guardian.
- **Headers:**
  - `X-Auth-Email`: guardian email
  - `X-Auth-Password`: guardian password
- **Payload (JSON):**
  ```json
  {
    "first_name": "Jane",
    "last_name": "Doe",           // optional
    "date_of_birth": "2015-03-20" // optional
  }
  ```
- **Response (JSON):**
  - On success (201):
    ```json
    {
      "status": "ok",
      "message": "Child added successfully",
      "child": {
        "child_hash": "...",
        "first_name": "Jane",
        "last_name": "Doe",
        "date_of_birth": "2015-03-20"
      }
    }
    ```
  - On error (missing/invalid): `{ "error": "<error_message>" }`
# Accounts & Authentication API Endpoints

---

## 9. Delete Guardian Account
- **URL:** `/accounts/delete-account/`
- **Method:** `POST`
- **Auth:** Email and password required in payload (no login required)
- **Description:** Deletes the specified guardian account, all children registered under that account, and all related data (documents, screen time, messaging, etc.).
- **Payload (JSON):**
  - `email` (string, required)
  - `password` (string, required)
- **Response (JSON):**
  - On success:
    ```json
    {
      "status": "success",
      "message": "Account <email> and all related data have been deleted."
    }
    ```
  - On error (invalid credentials):
    ```json
    {
      "status": "error",
      "message": "Invalid credentials."
    }
    ```
  - On error (other):
    ```json
    {
      "status": "error",
      "message": "An error occurred: <error_message>"
    }
    ```

This document describes the API endpoints for the `accounts` app, including authentication, child management, and profile image handling. Each endpoint includes the URL, HTTP method(s), payload structure, and response structure.

---

## 1. Landing Page
- **URL:** `/accounts/`
- **Method:** `GET`
- **Description:** Serves the landing page (HTML).
- **Payload:** None
- **Response:** HTML page

---

## 2. Signup
- **URL:** `/accounts/signup/`
- **Method:** `GET`, `POST`
- **Description:** Register a new guardian account.
- **Payload (POST):**
  - `email` (string, required)
  - `password` (string, required)
  - `full_name` (string, optional)
- **Response:**
  - On success: Redirects to dashboard
  - On failure: Renders signup page with error message

---

## 3. Login
- **URL:** `/accounts/login/`
- **Method:** `GET`, `POST`
- **Description:** Log in as a guardian.
- **Payload (POST):**
  - `email` (string, required)
  - `password` (string, required)
- **Response:**
  - On success: Redirects to dashboard
  - On failure: Renders login page with error message

---

## 4. Logout
- **URL:** `/accounts/logout/`
- **Method:** `GET`
- **Description:** Log out the current user.
- **Payload:** None
- **Response:** Redirects to login page

---

## 5. Password Reset Info
- **URL:** `/accounts/password-reset/`
- **Method:** `GET`
- **Description:** Shows password reset info page (for production, use Django's built-in password reset views).
- **Payload:** None
- **Response:** HTML page

---

## 6. Delete Child
- **URL:** `/accounts/child/<child_hash>/delete/`
- **Method:** `POST`
- **Auth:** Guardian must be logged in and own the child
- **Description:** Deletes a child and all related data (CASCADE delete).
- **Payload:** None (child_hash in URL)
- **Response (JSON):**
  - On success:
    ```json
    {
      "status": "success",
      "message": "<child_name> has been deleted successfully."
    }
    ```
  - On error (permission or other):
    ```json
    {
      "status": "error",
      "message": "You do not have permission to delete this child."
    }
    ```
  - On server error:
    ```json
    {
      "status": "error",
      "message": "An error occurred: <error_message>"
    }
    ```

---

## 7. Upload Child Profile Image
- **URL:** `/accounts/child/<child_hash>/upload-profile-image/`
- **Method:** `POST`
- **Auth:** Guardian must be logged in and own the child
- **Description:** Upload or update a child's profile image. Accepts image files (jpg, jpeg, png, gif, webp, max 5MB). Converts to WEBP.
- **Payload (multipart/form-data):**
  - `profile_image` (file, required)
- **Response (JSON):**
  - On success:
    ```json
    {
      "status": "success",
      "message": "Profile image updated successfully.",
      "image_url": "<url_to_image>"
    }
    ```
  - On error (permission, file type, size, or invalid image):
    ```json
    {
      "status": "error",
      "message": "<error_message>"
    }
    ```
  - On server error:
    ```json
    {
      "status": "error",
      "message": "An error occurred: <error_message>"
    }
    ```

---

## 8. Get Profile Image
- **URL:** `/accounts/get-profile-image/`
- **Method:** `GET` or `POST`
- **Description:** Retrieve a child's profile image by `child_hash`.
- **Payload:**
  - `child_hash` (string, required; as query param for GET or form data for POST)
- **Response:**
  - On success: Image file (Content-Type: image/webp)
  - On error: 400 or 404 with plain text message

---

# Notes
- All endpoints requiring authentication use Django's session authentication (login required).
- Error messages are returned as JSON for API endpoints, or as rendered HTML for form-based endpoints.
- For production password reset, use Django's built-in password reset views for security.
