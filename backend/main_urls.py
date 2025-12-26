"""
Guardian AI - Main URL Configuration
Include mobile API and ingest endpoints
"""

from django.urls import path, include
from . import ingest_api_views

# Add these to your main urls.py
urlpatterns = [
    # Mobile API endpoints for parent dashboard
    path('api/mobile/', include('backend.mobile_api_urls')),
    
    # Data ingestion endpoint for child devices
    path('api/ingest/', ingest_api_views.ingest_data, name='ingest_data'),
]
