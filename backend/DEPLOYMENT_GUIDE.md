# Guardian AI Backend - Deployment Guide

## 📋 Complete Implementation Summary

All parent dashboard API endpoints have been implemented:

### ✅ Implemented Endpoints

1. **GET /api/mobile/children/** - List all children
2. **GET /api/mobile/child/<hash>/metrics/** - Aggregated overview  
3. **GET /api/mobile/child/<hash>/screen-time/** - Daily trend data
4. **GET /api/mobile/child/<hash>/app-usage/** - Per-app breakdown
5. **GET /api/mobile/child/<hash>/locations/** - Location history
6. **GET /api/mobile/child/<hash>/site-access/** - Site access logs
7. **GET/POST /api/mobile/child/<hash>/restricted-apps/** - App restrictions

### 📁 Files Created

```
backend/
├── models.py                  # Database models
├── mobile_api_views.py        # API endpoint implementations
├── ingest_api_views.py        # Data ingestion endpoint
├── helpers.py                 # Authentication & utilities
├── mobile_api_urls.py         # URL routing
├── main_urls.py               # Main URL configuration
├── admin.py                   # Django admin interface
├── requirements.txt           # Python dependencies
└── settings_config.py         # Django settings example
```

## 🚀 Deployment Steps

### 1. Install Dependencies

```bash
cd backend
pip install -r requirements.txt
```

### 2. Configure Settings

Add the configurations from `settings_config.py` to your Django project's `settings.py`:

```python
# In your main settings.py
INSTALLED_APPS = [
    # ... existing apps ...
    'rest_framework',
    'corsheaders',
    'backend',  # Your app
]

MIDDLEWARE = [
    # ... existing middleware ...
    'corsheaders.middleware.CorsMiddleware',  # Add this
]

# Add CORS settings
CORS_ALLOWED_ORIGINS = ["https://seraphguardlabs.com"]
CORS_ALLOW_CREDENTIALS = True
CORS_ALLOW_HEADERS = ['x-email', 'x-password', 'content-type', 'authorization']
```

### 3. Configure URLs

In your main `urls.py`:

```python
from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path('admin/', admin.site.urls),
    
    # Add these lines:
    path('api/mobile/', include('backend.mobile_api_urls')),
    path('api/ingest/', include('backend.ingest_api_views')),
]
```

### 4. Run Migrations

```bash
python manage.py makemigrations backend
python manage.py migrate
```

### 5. Create Superuser

```bash
python manage.py createsuperuser
```

### 6. Test Locally

```bash
python manage.py runserver
```

Test endpoints:
- http://localhost:8000/api/mobile/children/
- http://localhost:8000/admin/

## 🔐 Authentication

All endpoints use header-based authentication:

```
X-Email: parent@example.com
X-Password: password123
```

## 📊 Database Schema

### Guardian
- Links to Django User model
- Stores parent information

### Child
- `child_hash`: Unique identifier
- Links to Guardian
- Profile information

### ScreenTime
- Daily screen time data
- App-wise breakdown (JSON field)

### Location
- GPS coordinates with timestamp
- Optional address field

### SiteAccess
- Website visit logs
- Accessed/Blocked status

### AppRestriction
- App-wise time limits
- Synced to child devices

## 🔄 Data Flow

### Child Device → Backend
```
POST /api/ingest/
{
  "screen_time_info": {...},
  "location_info": {...},
  "site_access_info": {...}
}
```

### Parent App → Backend
```
GET /api/mobile/child/<hash>/metrics/
Headers:
  X-Email: parent@example.com
  X-Password: password
```

## 📝 Example Usage

### 1. Get All Children
```bash
curl -H "X-Email: parent@example.com" \
     -H "X-Password: password123" \
     https://seraphguardlabs.com/api/mobile/children/
```

### 2. Get Child Metrics
```bash
curl -H "X-Email: parent@example.com" \
     -H "X-Password: password123" \
     "https://seraphguardlabs.com/api/mobile/child/abc123/metrics/?start_date=2025-12-01&end_date=2025-12-26"
```

### 3. Set App Restriction
```bash
curl -X POST \
     -H "X-Email: parent@example.com" \
     -H "X-Password: password123" \
     -H "Content-Type: application/json" \
     -d '{"action":"add","package":"com.instagram.android","hours":2.0}' \
     https://seraphguardlabs.com/api/mobile/child/abc123/restricted-apps/
```

## 🛡️ Security Notes

1. **Production**: Set `DEBUG = False`
2. **HTTPS**: Always use SSL in production
3. **Secret Key**: Generate unique secret key
4. **Database**: Use PostgreSQL or MySQL in production
5. **CORS**: Restrict allowed origins
6. **Rate Limiting**: Consider adding rate limiting middleware

## 📦 Production Deployment (PythonAnywhere/Heroku)

### For PythonAnywhere:
1. Upload files to `/home/yourusername/guardian_ai/backend/`
2. Configure WSGI file to point to your Django app
3. Set up virtual environment
4. Run migrations
5. Collect static files: `python manage.py collectstatic`

### For Heroku:
1. Add `Procfile`: `web: gunicorn guardian_ai.wsgi`
2. Add `runtime.txt`: `python-3.11.0`
3. Configure database (PostgreSQL addon)
4. Set environment variables
5. Deploy via Git

## 🧪 Testing

Create test data:
```python
python manage.py shell

from backend.models import Guardian, Child
from django.contrib.auth.models import User

# Create guardian
user = User.objects.create_user('parent@test.com', 'parent@test.com', 'password123')
guardian = Guardian.objects.create(user=user, email='parent@test.com', first_name='John', last_name='Doe')

# Create child
child = Child.objects.create(
    guardian=guardian,
    first_name='Emma',
    last_name='Doe',
    date_of_birth='2015-05-20'
)

print(f"Child Hash: {child.child_hash}")
```

## 📱 Mobile App Integration

Update your Flutter/Dart API service to use these endpoints:

```dart
static const String baseUrl = 'https://seraphguardlabs.com';
```

All endpoints are already implemented in `lib/services/api_service.dart`.

## ✅ Implementation Complete!

All 7 API endpoints are ready for deployment to https://seraphguardlabs.com
