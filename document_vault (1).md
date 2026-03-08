# Document Vault API Endpoints

This document describes the API endpoints for the `document_vault` app, including dashboard, folder, document, trash, quota, sharing, bulk, and search operations. Each endpoint includes the URL, HTTP method(s), authentication requirements, headers, payload structure, and response structure.

---

## Authentication

All API endpoints (except the public share link access) require authentication via one of the following methods:

### 1. Session Authentication (Web/Browser)
- Log in via the standard Django login flow to obtain a session cookie.
- **Required Headers:**
  - `Cookie: sessionid=<session_id>` — Set automatically by the browser after login.
  - `X-CSRFToken: <csrf_token>` — Required for all state-changing requests (`POST`, `PUT`, `PATCH`, `DELETE`). Obtain the CSRF token from the `csrftoken` cookie.
  - `Content-Type: application/json` — For JSON request bodies.

### 2. Mobile Header Authentication (Mobile/API clients)
- Authenticate per-request using credential headers (no session required).
- **Required Headers:**
  - `X-Email: <guardian_email>` — The guardian's registered email address.
  - `X-Password: <guardian_password>` — The guardian's password.
  - `Content-Type: application/json` — For JSON request bodies.

### Rate Limiting
- Anonymous requests: **100/hour**
- Authenticated requests: **1000/hour**
- Mobile API: **50/minute**

### Response Format
All API responses are returned as **JSON only** (`application/json`). The standard response envelope is:
```json
{
  "status": "success" | "error",
  "message": "Human-readable message (on success/error)",
  ...additional fields
}
```

---

## 1. Dashboard

### Render Vault Dashboard
- **URL:** `/vault/`
- **Method:** `GET`
- **Auth:** Session login required (`@login_required` — redirects to login page if unauthenticated)
- **Description:** Renders the document vault dashboard HTML page with root folders, recent documents (latest 10), starred items, and storage quota usage.
- **Response:** HTML page (template: `document_vault/dashboard.html`)

---

## 2. Child-based Storage APIs

### List Children for Vault
- **URL:** `/api/vault/children/`
- **Method:** `GET`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - Session: `Cookie: sessionid=...`
  - Mobile: `X-Email`, `X-Password`
- **Description:** List all children belonging to the authenticated guardian, including per-child vault storage statistics.
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "children": [
      {
        "id": 1,
        "name": "John Doe",
        "child_hash": "abc123def456",
        "profile_image": "/media/profile_pictures/photo.jpg",
        "vault_stats": {
          "total_size": 2097152,
          "formatted_size": "2.0 MB",
          "file_count": 15,
          "folder_count": 3
        }
      }
    ]
  }
  ```

### Child Vault Overview
- **URL:** `/api/vault/children/<child_hash>/`
- **Method:** `GET`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - Session: `Cookie: sessionid=...`
  - Mobile: `X-Email`, `X-Password`
- **URL Parameters:**
  - `child_hash` (string, required): The unique hash identifier of the child.
- **Description:** Get a complete overview of a child's vault contents including storage stats, root folders, recent documents (latest 10), and file category breakdown.
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "child": {
      "id": 1,
      "name": "John Doe",
      "child_hash": "abc123def456"
    },
    "stats": {
      "total_size": 2097152,
      "formatted_size": "2.0 MB",
      "file_count": 15,
      "folder_count": 3
    },
    "root_folders": [
      {
        "id": 1,
        "name": "Homework",
        "color": "#4A90D9",
        "document_count": 5,
        "total_size": 1048576
      }
    ],
    "recent_documents": [
      {
        "id": 10,
        "name": "Assignment.pdf",
        "file_category": "document",
        "formatted_size": "1.0 MB",
        "created_at": "2026-02-14T10:30:00+00:00"
      }
    ],
    "category_breakdown": [
      {
        "category": "document",
        "count": 10,
        "size": 1048576,
        "formatted_size": "1.0 MB"
      },
      {
        "category": "image",
        "count": 5,
        "size": 524288,
        "formatted_size": "512.0 KB"
      }
    ]
  }
  ```
- **Error Responses:**
  - `404 Not Found`: `{"status": "error", "message": "Invalid child_hash"}`

---

## 3. Folder APIs

### List Folders
- **URL:** `/api/vault/folders/`
- **Method:** `GET`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - Session: `Cookie: sessionid=...`
  - Mobile: `X-Email`, `X-Password`
- **Query Parameters:**
  | Parameter   | Type   | Required | Description |
  |-------------|--------|----------|-------------|
  | `parent_id` | int    | No       | Filter by parent folder ID. If omitted, returns root-level folders only. |
  | `child_hash`| string | No       | Filter folders by child. |
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "folders": [
      {
        "id": 1,
        "name": "Homework",
        "description": "Math assignments",
        "color": "#4A90D9",
        "is_starred": false,
        "parent_id": null,
        "child_id": 2,
        "child_hash": "abc123def456",
        "created_at": "2026-02-14T10:30:00+00:00",
        "document_count": 5,
        "total_size": 1048576,
        "formatted_size": "1.0 MB"
      }
    ]
  }
  ```
- **Error Responses:**
  - `404 Not Found`: `{"status": "error", "message": "Invalid child_hash"}`
  - `500 Internal Server Error`: `{"status": "error", "message": "An error occurred while listing folders"}`

### Create Folder
- **URL:** `/api/vault/folders/create/`
- **Method:** `POST`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - `Content-Type: application/json`
  - Session: `Cookie: sessionid=...` + `X-CSRFToken: <token>`
  - Mobile: `X-Email`, `X-Password`
- **Request Body (JSON):**
  | Field        | Type   | Required | Default     | Description |
  |--------------|--------|----------|-------------|-------------|
  | `name`       | string | **Yes**  | —           | Folder name (max 255 chars). Whitespace is trimmed. |
  | `parent_id`  | int    | No       | `null`      | ID of parent folder. Omit for root-level folder. |
  | `child_hash` | string | No       | `null`      | Child hash to associate with. If omitted and `parent_id` is provided, inherits child from parent. |
  | `description`| string | No       | `""`        | Optional folder description. |
  | `color`      | string | No       | `"#4A90D9"` | Folder color as hex code (max 7 chars, e.g. `"#FF5733"`). |
- **Response (201 Created):**
  ```json
  {
    "status": "success",
    "message": "Folder \"Homework\" created successfully",
    "folder": {
      "id": 1,
      "name": "Homework"
    }
  }
  ```
- **Error Responses:**
  - `400 Bad Request`: `{"status": "error", "message": "Folder name is required"}`
  - `400 Bad Request`: `{"status": "error", "message": "A folder with this name already exists in this location"}`
  - `404 Not Found`: `{"status": "error", "message": "Invalid child_hash"}`
  - `404 Not Found`: Parent folder not found (Django 404 page or DRF 404 JSON).
  - `500 Internal Server Error`: `{"status": "error", "message": "An error occurred while creating the folder"}`

### Folder Details
- **URL:** `/api/vault/folders/<folder_id>/`
- **Method:** `GET`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - Session: `Cookie: sessionid=...`
  - Mobile: `X-Email`, `X-Password`
- **URL Parameters:**
  - `folder_id` (int, required): The folder ID.
- **Description:** Get folder details including subfolders, documents (non-deleted), and breadcrumb path from root.
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "folder": {
      "id": 1,
      "name": "Homework",
      "description": "Math assignments",
      "color": "#4A90D9",
      "is_starred": false,
      "created_at": "2026-02-14T10:30:00+00:00",
      "full_path": "/School/Homework"
    },
    "subfolders": [
      {
        "id": 3,
        "name": "Math",
        "color": "#4A90D9",
        "is_starred": false,
        "document_count": 2
      }
    ],
    "documents": [
      {
        "id": 10,
        "name": "Assignment.pdf",
        "file_size": 1048576,
        "formatted_size": "1.0 MB",
        "file_category": "document",
        "is_starred": false,
        "created_at": "2026-02-14T10:30:00+00:00"
      }
    ],
    "breadcrumb": [
      {"id": 5, "name": "School"},
      {"id": 1, "name": "Homework"}
    ]
  }
  ```
- **Error Responses:**
  - `404 Not Found`: Folder not found or does not belong to the authenticated guardian.

### Update Folder
- **URL:** `/api/vault/folders/<folder_id>/update/`
- **Method:** `PUT` or `PATCH`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - `Content-Type: application/json`
  - Session: `Cookie: sessionid=...` + `X-CSRFToken: <token>`
  - Mobile: `X-Email`, `X-Password`
- **URL Parameters:**
  - `folder_id` (int, required): The folder ID.
- **Request Body (JSON):** All fields are optional. Only provided fields are updated.
  | Field        | Type    | Description |
  |--------------|---------|-------------|
  | `name`       | string  | New folder name (max 255 chars). Checked for duplicates in the same parent. |
  | `description`| string  | New folder description. |
  | `color`      | string  | New hex color code (max 7 chars). |
  | `is_starred` | boolean | Star/unstar the folder. |
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "message": "Folder updated successfully",
    "folder": {
      "id": 1,
      "name": "Homework",
      "description": "Updated description",
      "color": "#FF5733",
      "is_starred": true
    }
  }
  ```
- **Error Responses:**
  - `400 Bad Request`: `{"status": "error", "message": "A folder with this name already exists in this location"}`
  - `404 Not Found`: Folder not found or does not belong to the authenticated guardian.

### Delete Folder
- **URL:** `/api/vault/folders/<folder_id>/delete/`
- **Method:** `DELETE`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - Session: `Cookie: sessionid=...` + `X-CSRFToken: <token>`
  - Mobile: `X-Email`, `X-Password`
- **URL Parameters:**
  - `folder_id` (int, required): The folder ID.
- **Description:** Permanently deletes the folder, all subfolders (recursively), and all contained documents (including from storage). Storage quota is recalculated after deletion. **This action cannot be undone.**
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "message": "Folder \"Homework\" and its contents deleted successfully",
    "deleted": {
      "documents": 5,
      "subfolders": 2,
      "total_size": 5242880
    }
  }
  ```
- **Error Responses:**
  - `404 Not Found`: `{"status": "error", "message": "Folder not found"}`
  - `500 Internal Server Error`: `{"status": "error", "message": "An error occurred while deleting the folder"}`

---

## 4. Document APIs

### List Documents
- **URL:** `/api/vault/documents/`
- **Method:** `GET`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - Session: `Cookie: sessionid=...`
  - Mobile: `X-Email`, `X-Password`
- **Query Parameters:**
  | Parameter      | Type    | Required | Default   | Description |
  |----------------|---------|----------|-----------|-------------|
  | `folder_id`    | int or `"root"` | No | — | Filter by folder ID. Use `"root"` to get documents not in any folder. |
  | `child_hash`   | string  | No       | —         | Filter documents by child. |
  | `category`     | string  | No       | —         | Filter by file category (e.g. `"document"`, `"image"`, `"audio"`, `"video"`, `"archive"`). |
  | `search`       | string  | No       | —         | Search in `display_name`, `original_filename`, and `description` (case-insensitive). |
  | `show_deleted` | string  | No       | `"false"` | Set to `"true"` to list only trashed documents. |
  | `starred_only` | string  | No       | `"false"` | Set to `"true"` to list only starred documents. |
- **Max Results:** 100 documents per request.
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "documents": [
      {
        "id": 1,
        "name": "Assignment.pdf",
        "original_filename": "Assignment.pdf",
        "file_size": 1048576,
        "formatted_size": "1.0 MB",
        "file_category": "document",
        "file_extension": ".pdf",
        "mime_type": "application/pdf",
        "is_starred": false,
        "is_deleted": false,
        "folder_id": 2,
        "created_at": "2026-02-14T10:30:00+00:00",
        "tags": ["math", "homework"]
      }
    ],
    "count": 1
  }
  ```
- **Error Responses:**
  - `404 Not Found`: `{"status": "error", "message": "Invalid child_hash"}`

### Upload Document
- **URL:** `/api/vault/documents/upload/`
- **Method:** `POST`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - `Content-Type: multipart/form-data` (automatically set by clients when uploading files)
  - Session: `Cookie: sessionid=...` + `X-CSRFToken: <token>`
  - Mobile: `X-Email`, `X-Password`
- **Request Body (`multipart/form-data`):**
  | Field          | Type       | Required | Default | Description |
  |----------------|------------|----------|---------|-------------|
  | `file`         | file       | **Yes**  | —       | The file to upload. Max size: **50 MB**. See allowed types below. |
  | `folder_id`    | int        | No       | `null`  | Target folder ID. If the folder has an associated child, the document inherits it. |
  | `child_hash`   | string     | No       | `null`  | Child hash to associate the document with. |
  | `description`  | string     | No       | `""`    | Optional file description. |
  | `display_name` | string     | No       | Original filename | Custom display name for the document. |
  | `tags`         | JSON string| No       | `"[]"`  | JSON array of tag strings, e.g. `'["math", "homework"]'`. |
- **File Validation:**
  - Maximum file size: 50 MB
  - Blocked extensions: executables (`.exe`, `.bat`, `.sh`, etc.), scripts (`.py`, `.js`, `.php`, etc.), system files (`.dll`, `.sys`, etc.), and other potentially dangerous formats.
  - Allowed MIME types: documents (PDF, Word, Excel, PowerPoint, RTF, TXT, CSV), images (JPEG, PNG, GIF, WebP, BMP, TIFF, HEIC), audio (MP3, WAV, OGG, AAC, FLAC, M4A), video (MP4, MPEG, MOV, AVI, WebM, MKV), archives (ZIP, RAR, 7Z).
  - File content is scanned for suspicious patterns (embedded scripts, executable signatures).
  - A SHA-256 checksum is computed and stored for integrity verification.
- **Quota Enforcement:**
  - Storage quota: default 5 GB per guardian.
  - File count quota: default 1000 files per guardian.
  - Upload is rejected if either quota is exceeded.
- **Response (201 Created):**
  ```json
  {
    "status": "success",
    "message": "Document \"Assignment.pdf\" uploaded successfully",
    "document": {
      "id": 1,
      "name": "Assignment.pdf"
    }
  }
  ```
- **Error Responses:**
  - `400 Bad Request`: `{"status": "error", "message": "No file provided"}`
  - `400 Bad Request`: `{"status": "error", "message": "Storage quota exceeded. You have 100.0 MB remaining."}`
  - `400 Bad Request`: `{"status": "error", "message": "File limit reached. Maximum 1000 files allowed."}`
  - `400 Bad Request`: `{"status": "error", "message": "File type \".exe\" is not allowed for security reasons..."}`
  - `404 Not Found`: `{"status": "error", "message": "Invalid child_hash"}`
  - `500 Internal Server Error`: `{"status": "error", "message": "An error occurred while uploading the document"}`

### Document Details
- **URL:** `/api/vault/documents/<document_id>/`
- **Method:** `GET`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - Session: `Cookie: sessionid=...`
  - Mobile: `X-Email`, `X-Password`
- **URL Parameters:**
  - `document_id` (int, required): The document ID.
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "document": {
      "id": 1,
      "name": "Assignment.pdf",
      "original_filename": "Assignment.pdf",
      "display_name": "Assignment.pdf",
      "file_size": 1048576,
      "formatted_size": "1.0 MB",
      "file_category": "document",
      "file_extension": ".pdf",
      "mime_type": "application/pdf",
      "description": "Math homework for chapter 5",
      "tags": ["math", "homework"],
      "is_starred": false,
      "is_deleted": false,
      "folder_id": 2,
      "created_at": "2026-02-14T10:30:00+00:00",
      "updated_at": "2026-02-15T08:00:00+00:00",
      "last_accessed_at": "2026-02-15T12:00:00+00:00",
      "access_count": 3,
      "checksum": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    }
  }
  ```
- **Error Responses:**
  - `404 Not Found`: Document not found or does not belong to the authenticated guardian.

### Update Document
- **URL:** `/api/vault/documents/<document_id>/update/`
- **Method:** `PUT` or `PATCH`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - `Content-Type: application/json`
  - Session: `Cookie: sessionid=...` + `X-CSRFToken: <token>`
  - Mobile: `X-Email`, `X-Password`
- **URL Parameters:**
  - `document_id` (int, required): The document ID.
- **Request Body (JSON):** All fields are optional. Only provided fields are updated.
  | Field          | Type     | Description |
  |----------------|----------|-------------|
  | `display_name` | string   | New display name for the document. Whitespace is trimmed. |
  | `description`  | string   | New description text. |
  | `tags`         | array    | New list of tag strings, e.g. `["math", "homework"]`. |
  | `is_starred`   | boolean  | Star/unstar the document. |
  | `folder_id`    | int/null | Move document to a folder (by ID) or set to `null` to move to root. |
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "message": "Document updated successfully",
    "document": {
      "id": 1,
      "name": "Assignment.pdf",
      "is_starred": true,
      "folder_id": 3
    }
  }
  ```
- **Error Responses:**
  - `404 Not Found`: Document not found or does not belong to the authenticated guardian.
  - `404 Not Found`: Target folder not found (if `folder_id` is provided).

### Delete Document
- **URL:** `/api/vault/documents/<document_id>/delete/`
- **Method:** `DELETE`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - Session: `Cookie: sessionid=...` + `X-CSRFToken: <token>`
  - Mobile: `X-Email`, `X-Password`
- **URL Parameters:**
  - `document_id` (int, required): The document ID.
- **Query Parameters:**
  | Parameter   | Type   | Required | Default   | Description |
  |-------------|--------|----------|-----------|-------------|
  | `permanent` | string | No       | `"false"` | Set to `"true"` to permanently delete (removes file from storage and database). Default is soft delete (move to trash). |
- **Response (200 OK) — Soft delete:**
  ```json
  {
    "status": "success",
    "message": "Document \"Assignment.pdf\" moved to trash"
  }
  ```
- **Response (200 OK) — Permanent delete:**
  ```json
  {
    "status": "success",
    "message": "Document \"Assignment.pdf\" permanently deleted"
  }
  ```
- **Error Responses:**
  - `404 Not Found`: Document not found or does not belong to the authenticated guardian.

### Restore Document
- **URL:** `/api/vault/documents/<document_id>/restore/`
- **Method:** `POST`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - Session: `Cookie: sessionid=...` + `X-CSRFToken: <token>`
  - Mobile: `X-Email`, `X-Password`
- **URL Parameters:**
  - `document_id` (int, required): The document ID. Must be a trashed document (`is_deleted=True`).
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "message": "Document \"Assignment.pdf\" restored from trash"
  }
  ```
- **Error Responses:**
  - `404 Not Found`: Document not found, does not belong to the authenticated guardian, or is not in trash.

### Download Document
- **URL:** `/api/vault/documents/<document_id>/download/`
- **Method:** `GET`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - Session: `Cookie: sessionid=...`
  - Mobile: `X-Email`, `X-Password`
- **URL Parameters:**
  - `document_id` (int, required): The document ID. Must not be in trash.
- **Description:** Returns a download URL for the document. Records access (increments `access_count` and updates `last_accessed_at`).
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "download_url": "/media/document_vault/abc123/file.pdf",
    "filename": "Assignment.pdf",
    "mime_type": "application/pdf"
  }
  ```
- **Error Responses:**
  - `404 Not Found`: `{"status": "error", "message": "Document not found"}` or `{"status": "error", "message": "File not available"}`
  - `500 Internal Server Error`: `{"status": "error", "message": "An error occurred while fetching the download URL"}`

---

## 5. Trash APIs

### List Trash
- **URL:** `/api/vault/trash/`
- **Method:** `GET`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - Session: `Cookie: sessionid=...`
  - Mobile: `X-Email`, `X-Password`
- **Description:** List all soft-deleted documents belonging to the authenticated guardian, ordered by most recently deleted.
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "documents": [
      {
        "id": 5,
        "name": "OldFile.pdf",
        "file_size": 524288,
        "formatted_size": "512.0 KB",
        "file_category": "document",
        "deleted_at": "2026-03-01T14:00:00+00:00"
      }
    ],
    "count": 1
  }
  ```

### Empty Trash
- **URL:** `/api/vault/trash/empty/`
- **Method:** `POST`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - Session: `Cookie: sessionid=...` + `X-CSRFToken: <token>`
  - Mobile: `X-Email`, `X-Password`
- **Description:** Permanently deletes all trashed documents, removes files from storage, and recalculates the guardian's storage quota. **This action cannot be undone.**
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "message": "Trash emptied. 3 documents permanently deleted.",
    "deleted_count": 3,
    "freed_space": "1.5 MB"
  }
  ```

---

## 6. Storage Quota API

### Get Storage Quota
- **URL:** `/api/vault/quota/`
- **Method:** `GET`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - Session: `Cookie: sessionid=...`
  - Mobile: `X-Email`, `X-Password`
- **Description:** Get the authenticated guardian's current storage quota usage, limits, and remaining capacity.
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "quota": {
      "used_storage_bytes": 104857600,
      "max_storage_bytes": 5368709120,
      "formatted_used": "100.0 MB",
      "formatted_max": "5.0 GB",
      "percentage_used": 2.0,
      "remaining_bytes": 5263851520,
      "formatted_remaining": "4.9 GB",
      "current_file_count": 25,
      "max_file_count": 1000
    }
  }
  ```

---

## 7. Share Links APIs

### Create Share Link
- **URL:** `/api/vault/documents/<document_id>/share/`
- **Method:** `POST`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - `Content-Type: application/json`
  - Session: `Cookie: sessionid=...` + `X-CSRFToken: <token>`
  - Mobile: `X-Email`, `X-Password`
- **URL Parameters:**
  - `document_id` (int, required): The document ID. Must not be in trash.
- **Request Body (JSON):** All fields are optional.
  | Field           | Type   | Required | Default     | Description |
  |-----------------|--------|----------|-------------|-------------|
  | `expires_hours` | int    | No       | `null`      | Number of hours until the link expires. `null` = never expires. |
  | `max_downloads` | int    | No       | `null`      | Maximum number of downloads allowed. `null` = unlimited. |
  | `password`      | string | No       | `""`        | Optional password to protect the link. Stored as SHA-256 hash. |
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "share_link": {
      "token": "dGhpcyBpcyBhIHRlc3QgdG9rZW4",
      "url": "/vault/share/dGhpcyBpcyBhIHRlc3QgdG9rZW4/",
      "expires_at": "2026-03-09T10:30:00+00:00",
      "max_downloads": 10,
      "has_password": true
    }
  }
  ```
- **Error Responses:**
  - `404 Not Found`: Document not found, does not belong to the authenticated guardian, or is in trash.

### List Share Links
- **URL:** `/api/vault/documents/<document_id>/shares/`
- **Method:** `GET`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - Session: `Cookie: sessionid=...`
  - Mobile: `X-Email`, `X-Password`
- **URL Parameters:**
  - `document_id` (int, required): The document ID.
- **Description:** List all share links for a document, ordered by most recently created.
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "links": [
      {
        "id": 1,
        "token": "dGhpcyBpcyBhIHRlc3QgdG9rZW4",
        "url": "/vault/share/dGhpcyBpcyBhIHRlc3QgdG9rZW4/",
        "created_at": "2026-03-08T10:30:00+00:00",
        "expires_at": "2026-03-09T10:30:00+00:00",
        "max_downloads": 10,
        "download_count": 3,
        "is_active": true,
        "is_valid": true,
        "has_password": true
      }
    ]
  }
  ```
- **Error Responses:**
  - `404 Not Found`: Document not found or does not belong to the authenticated guardian.

### Delete Share Link
- **URL:** `/api/vault/shares/<link_id>/delete/`
- **Method:** `DELETE`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - Session: `Cookie: sessionid=...` + `X-CSRFToken: <token>`
  - Mobile: `X-Email`, `X-Password`
- **URL Parameters:**
  - `link_id` (int, required): The share link ID.
- **Description:** Permanently delete a share link. Only the guardian who owns the linked document can delete it.
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "message": "Share link deleted"
  }
  ```
- **Error Responses:**
  - `404 Not Found`: Share link not found or the linked document does not belong to the authenticated guardian.

### Access Shared Document (Public)
- **URL:** `/vault/share/<token>/`
- **Method:** `GET`, `POST`
- **Auth:** **None** — This endpoint is publicly accessible (`AllowAny`).
- **URL Parameters:**
  - `token` (string, required): The unique share token.

#### GET — Check Link & Document Info
- **Description:** Check if the share link is valid and whether a password is required. Returns basic document metadata.
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "requires_password": true,
    "document": {
      "name": "Assignment.pdf",
      "file_size": 1048576,
      "formatted_size": "1.0 MB",
      "file_category": "document"
    }
  }
  ```

#### POST — Verify Password & Download
- **Required Headers:**
  - `Content-Type: application/json` (only if password-protected)
- **Request Body (JSON):** Required only if the link is password-protected.
  | Field      | Type   | Required | Description |
  |------------|--------|----------|-------------|
  | `password` | string | Conditional | Required if the link has a password set. |
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "download_url": "/media/document_vault/abc123/file.pdf",
    "filename": "Assignment.pdf"
  }
  ```
- **Error Responses (both GET and POST):**
  - `404 Not Found`: Share link token not found.
  - `410 Gone`: `{"status": "error", "message": "This share link has expired"}`
  - `410 Gone`: `{"status": "error", "message": "This share link has reached its download limit"}`
  - `410 Gone`: `{"status": "error", "message": "This share link is no longer active"}`
  - `401 Unauthorized`: `{"status": "error", "message": "Incorrect password"}` (POST only)

---

## 8. Bulk Operations APIs

### Bulk Move
- **URL:** `/api/vault/bulk/move/`
- **Method:** `POST`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - `Content-Type: application/json`
  - Session: `Cookie: sessionid=...` + `X-CSRFToken: <token>`
  - Mobile: `X-Email`, `X-Password`
- **Request Body (JSON):**
  | Field          | Type       | Required | Description |
  |----------------|------------|----------|-------------|
  | `document_ids` | array[int] | **Yes**  | List of document IDs to move. |
  | `folder_id`    | int/null   | No       | Target folder ID. Set to `null` or omit to move to root level. |
- **Description:** Move multiple non-deleted documents to a target folder. Only documents belonging to the authenticated guardian are affected.
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "message": "5 documents moved successfully",
    "moved_count": 5
  }
  ```
- **Error Responses:**
  - `400 Bad Request`: `{"status": "error", "message": "No documents specified"}`
  - `404 Not Found`: Target folder not found or does not belong to the authenticated guardian.

### Bulk Delete
- **URL:** `/api/vault/bulk/delete/`
- **Method:** `POST`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - `Content-Type: application/json`
  - Session: `Cookie: sessionid=...` + `X-CSRFToken: <token>`
  - Mobile: `X-Email`, `X-Password`
- **Request Body (JSON):**
  | Field          | Type       | Required | Default | Description |
  |----------------|------------|----------|---------|-------------|
  | `document_ids` | array[int] | **Yes**  | —       | List of document IDs to delete. |
  | `permanent`    | boolean    | No       | `false` | If `true`, permanently deletes documents and files from storage. If `false`, moves to trash (soft delete). |
- **Response (200 OK) — Soft delete:**
  ```json
  {
    "status": "success",
    "message": "5 documents moved to trash",
    "deleted_count": 5
  }
  ```
- **Response (200 OK) — Permanent delete:**
  ```json
  {
    "status": "success",
    "message": "5 documents permanently deleted",
    "deleted_count": 5
  }
  ```
- **Error Responses:**
  - `400 Bad Request`: `{"status": "error", "message": "No documents specified"}`

---

## 9. Search API

### Search Vault
- **URL:** `/api/vault/search/`
- **Method:** `GET`
- **Auth:** `IsAuthenticated` (Session or Mobile Header)
- **Required Headers:**
  - Session: `Cookie: sessionid=...`
  - Mobile: `X-Email`, `X-Password`
- **Query Parameters:**
  | Parameter | Type   | Required | Description |
  |-----------|--------|----------|-------------|
  | `q`       | string | **Yes**  | Search query. Searches in document `display_name`, `original_filename`, `description`, and folder `name`, `description` (case-insensitive). |
- **Max Results:** 20 documents, 10 folders.
- **Response (200 OK):**
  ```json
  {
    "status": "success",
    "query": "math",
    "documents": [
      {
        "id": 1,
        "name": "Math Assignment.pdf",
        "file_category": "document",
        "formatted_size": "1.0 MB",
        "folder_id": 2
      }
    ],
    "folders": [
      {
        "id": 3,
        "name": "Math",
        "color": "#4A90D9",
        "full_path": "/School/Math"
      }
    ]
  }
  ```
- **Error Responses:**
  - `400 Bad Request`: `{"status": "error", "message": "Search query required"}`

---

## Notes

- **Authentication:** All API endpoints require authentication (`IsAuthenticated`) via either Session cookies or Mobile Header credentials (`X-Email`/`X-Password`), except the public share link access endpoint.
- **CSRF Protection:** When using Session authentication, all state-changing requests (`POST`, `PUT`, `PATCH`, `DELETE`) require a valid CSRF token in the `X-CSRFToken` header. The token can be read from the `csrftoken` cookie. Mobile Header authentication does not require CSRF tokens.
- **Response Format:** All API responses use `application/json`. The dashboard view (`/vault/`) returns HTML.
- **Ownership Scoping:** All queries are automatically scoped to the authenticated guardian — a guardian can only access their own folders, documents, and associated data.
- **Soft Delete:** Documents are soft-deleted by default (moved to trash). Permanent deletion must be explicitly requested via the `permanent` query/body parameter.
- **Storage Quotas:** Default limits are 5 GB storage and 1000 files per guardian. Uploads are blocked if either limit is exceeded.
- **File Security:** Uploaded files are validated for extension, MIME type, and content patterns. Dangerous file types (executables, scripts, system files) are rejected.
