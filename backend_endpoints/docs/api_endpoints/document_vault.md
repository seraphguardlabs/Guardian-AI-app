# Document Vault API Endpoints

This document describes the API endpoints for the `document_vault` app, including dashboard, folder, document, trash, quota, sharing, bulk, and search operations. Each endpoint includes the URL, HTTP method(s), payload structure, and response structure.

---

## 1. Dashboard
- **URL:** `/vault/`
- **Method:** `GET`
- **Auth:** Session (guardian login required)
- **Description:** Renders the document vault dashboard with folders, recent documents, starred items, and storage usage.
- **Response:** HTML page

---

## 2. Child-based Storage APIs
- **List Children for Vault**
	- **URL:** `/api/vault/children/`
	- **Method:** `GET`
	- **Auth:** Session
	- **Description:** List all children for whom the guardian has vault access.
- **Child Vault Overview**
	- **URL:** `/api/vault/children/<child_hash>/`
	- **Method:** `GET`
	- **Auth:** Session
	- **Description:** Overview of vault usage and contents for a specific child.

---

## 3. Folder APIs
- **List Folders**
	- **URL:** `/api/vault/folders/`
	- **Method:** `GET`
	- **Auth:** Session
	- **Query Params:**
		- `parent_id` (optional): Filter by parent folder
		- `child_hash` (optional): Filter by child
	- **Response (JSON):**
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
					"child_hash": "abc123",
					"created_at": "2026-02-14T10:30:00Z",
					"document_count": 5,
					"total_size": 1048576,
					"formatted_size": "1.0 MB"
				}
			]
		}
		```
- **Create Folder**
	- **URL:** `/api/vault/folders/create/`
	- **Method:** `POST`
	- **Auth:** Session
	- **Payload (JSON):**
		- `name` (string, required)
		- `parent_id` (int, optional)
		- `child_hash` (string, optional)
		- `description` (string, optional)
		- `color` (string, optional)
	- **Response (JSON):**
		- On success: `{ "status": "success", ... }`
		- On error: `{ "status": "error", "message": "<error_message>" }`
- **Folder Details**
	- **URL:** `/api/vault/folders/<folder_id>/`
	- **Method:** `GET`
	- **Auth:** Session
	- **Description:** Get folder details, subfolders, documents, and breadcrumb path.
- **Update Folder**
	- **URL:** `/api/vault/folders/<folder_id>/update/`
	- **Method:** `PUT`, `PATCH`
	- **Auth:** Session
	- **Payload (JSON):**
		- Any of: `name`, `description`, `color`, `is_starred`
	- **Response (JSON):** `{ "status": "success", ... }`
- **Delete Folder**
	- **URL:** `/api/vault/folders/<folder_id>/delete/`
	- **Method:** `DELETE`
	- **Auth:** Session
	- **Response (JSON):** `{ "status": "success", "message": "...", "deleted": { ... } }`

---

## 4. Document APIs
- **List Documents**
	- **URL:** `/api/vault/documents/`
	- **Method:** `GET`
	- **Auth:** Session
	- **Query Params:**
		- `folder_id`, `child_hash`, `category`, `search`, `show_deleted`, `starred_only`
	- **Response (JSON):**
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
					"file_category": "pdf",
					"file_extension": "pdf",
					"mime_type": "application/pdf",
					"is_starred": false,
					"is_deleted": false,
					"folder_id": 2,
					"created_at": "2026-02-14T10:30:00Z",
					"tags": ["math", "homework"]
				}
			],
			"count": 1
		}
		```
- **Upload Document**
	- **URL:** `/api/vault/documents/upload/`
	- **Method:** `POST`
	- **Auth:** Session
	- **Payload (multipart/form-data):**
		- `file` (file, required)
		- `folder_id` (int, optional)
		- `child_hash` (string, optional)
		- `description` (string, optional)
		- `display_name` (string, optional)
		- `tags` (JSON array, optional)
	- **Response (JSON):** `{ "status": "success", ... }` or error
- **Document Details**
	- **URL:** `/api/vault/documents/<document_id>/`
	- **Method:** `GET`
	- **Auth:** Session
	- **Response (JSON):** `{ "status": "success", "document": { ... } }`
- **Update Document**
	- **URL:** `/api/vault/documents/<document_id>/update/`
	- **Method:** `PUT`, `PATCH`
	- **Auth:** Session
	- **Payload (JSON):**
		- Any of: `display_name`, `description`, `tags`, `is_starred`, `folder_id`
	- **Response (JSON):** `{ "status": "success", ... }`
- **Delete Document**
	- **URL:** `/api/vault/documents/<document_id>/delete/`
	- **Method:** `DELETE`
	- **Auth:** Session
	- **Query Param:** `permanent` (optional, if true, hard delete)
	- **Response (JSON):** `{ "status": "success", ... }`
- **Restore Document**
	- **URL:** `/api/vault/documents/<document_id>/restore/`
	- **Method:** `POST`
	- **Auth:** Session
	- **Response (JSON):** `{ "status": "success", ... }`
- **Download Document**
	- **URL:** `/api/vault/documents/<document_id>/download/`
	- **Method:** `GET`
	- **Auth:** Session
	- **Response (JSON):** `{ "status": "success", "download_url": "...", ... }`

---

## 5. Trash APIs
- **List Trash**
	- **URL:** `/api/vault/trash/`
	- **Method:** `GET`
	- **Auth:** Session
- **Empty Trash**
	- **URL:** `/api/vault/trash/empty/`
	- **Method:** `POST`
	- **Auth:** Session

---

## 6. Storage Quota API
- **URL:** `/api/vault/quota/`
- **Method:** `GET`
- **Auth:** Session

---

## 7. Share Links APIs
- **Create Share Link**
	- **URL:** `/api/vault/documents/<document_id>/share/`
	- **Method:** `POST`
	- **Auth:** Session
- **List Share Links**
	- **URL:** `/api/vault/documents/<document_id>/shares/`
	- **Method:** `GET`
	- **Auth:** Session
- **Delete Share Link**
	- **URL:** `/api/vault/shares/<link_id>/delete/`
	- **Method:** `DELETE`
	- **Auth:** Session
- **Access Shared Document (Public)**
	- **URL:** `/vault/share/<token>/`
	- **Method:** `GET`, `POST`
	- **Auth:** None (public)

---

## 8. Bulk Operations APIs
- **Bulk Move**
	- **URL:** `/api/vault/bulk/move/`
	- **Method:** `POST`
	- **Auth:** Session
- **Bulk Delete**
	- **URL:** `/api/vault/bulk/delete/`
	- **Method:** `POST`
	- **Auth:** Session

---

## 9. Search API
- **URL:** `/api/vault/search/`
- **Method:** `GET`
- **Auth:** Session

---

# Notes
- All endpoints require session authentication unless otherwise noted.
- Error messages are returned as JSON for all API endpoints.
- For detailed request/response examples, see the view docstrings or API responses.
