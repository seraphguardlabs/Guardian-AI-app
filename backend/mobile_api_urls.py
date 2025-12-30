"""
Guardian AI - Mobile API URL Configuration
URL patterns for parent mobile app endpoints
"""

from django.urls import path
from . import mobile_api_views

app_name = 'mobile_api'

urlpatterns = [
    # Children list
    path('children/', mobile_api_views.children_list, name='children_list'),
    
    # Child-specific endpoints
    path('child/<str:child_hash>/metrics/', mobile_api_views.child_metrics, name='child_metrics'),
    path('child/<str:child_hash>/screen-time/', mobile_api_views.screen_time_trend, name='screen_time_trend'),
    path('child/<str:child_hash>/app-usage/', mobile_api_views.app_usage_data, name='app_usage_data'),
    path('child/<str:child_hash>/locations/', mobile_api_views.location_history, name='location_history'),
    path('child/<str:child_hash>/site-access/', mobile_api_views.site_access_logs, name='site_access_logs'),
    path('child/<str:child_hash>/restricted-apps/', mobile_api_views.restricted_apps, name='restricted_apps'),
    path('child/<str:child_hash>/public-key/', mobile_api_views.child_public_key_update, name='child_public_key_update'),
    
    # Guardian endpoints
    path('guardian/public-key/', mobile_api_views.guardian_public_key_update, name='guardian_public_key_update'),
]
