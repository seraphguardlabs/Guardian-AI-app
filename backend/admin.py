"""
Guardian AI Backend - Django Admin Configuration
Admin interface for managing data
"""

from django.contrib import admin
from .models import Guardian, Child, ScreenTime, Location, SiteAccess, AppRestriction


@admin.register(Guardian)
class GuardianAdmin(admin.ModelAdmin):
    list_display = ['email', 'first_name', 'last_name', 'date_joined']
    search_fields = ['email', 'first_name', 'last_name']
    list_filter = ['date_joined']
    ordering = ['-date_joined']


@admin.register(Child)
class ChildAdmin(admin.ModelAdmin):
    list_display = ['child_hash', 'first_name', 'last_name', 'guardian', 'date_of_birth', 'age', 'is_active']
    search_fields = ['child_hash', 'first_name', 'last_name', 'guardian__email']
    list_filter = ['is_active', 'date_joined']
    ordering = ['-date_joined']
    readonly_fields = ['child_hash', 'age']


@admin.register(ScreenTime)
class ScreenTimeAdmin(admin.ModelAdmin):
    list_display = ['child', 'date', 'total_screen_time', 'app_count', 'created_at']
    search_fields = ['child__first_name', 'child__child_hash']
    list_filter = ['date', 'created_at']
    ordering = ['-date']
    
    def app_count(self, obj):
        return len(obj.app_wise_data.keys()) if obj.app_wise_data else 0
    app_count.short_description = 'Apps Used'


@admin.register(Location)
class LocationAdmin(admin.ModelAdmin):
    list_display = ['child', 'latitude', 'longitude', 'timestamp', 'address']
    search_fields = ['child__first_name', 'child__child_hash', 'address']
    list_filter = ['timestamp']
    ordering = ['-timestamp']


@admin.register(SiteAccess)
class SiteAccessAdmin(admin.ModelAdmin):
    list_display = ['child', 'domain', 'accessed', 'timestamp']
    search_fields = ['child__first_name', 'child__child_hash', 'domain', 'url']
    list_filter = ['accessed', 'timestamp']
    ordering = ['-timestamp']
    
    def get_queryset(self, request):
        qs = super().get_queryset(request)
        return qs.select_related('child')


@admin.register(AppRestriction)
class AppRestrictionAdmin(admin.ModelAdmin):
    list_display = ['child', 'package_name', 'app_name', 'hours_limit', 'minutes_limit', 'updated_at']
    search_fields = ['child__first_name', 'child__child_hash', 'package_name', 'app_name']
    list_filter = ['updated_at']
    ordering = ['child', 'package_name']
