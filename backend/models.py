"""
Guardian AI - Django Models
Database models for parent dashboard API
"""

from django.db import models
from django.contrib.auth.models import User
from django.utils import timezone
import secrets


class Guardian(models.Model):
    """Parent/Guardian account"""
    user = models.OneToOneField(User, on_delete=models.CASCADE)
    email = models.EmailField(unique=True)
    first_name = models.CharField(max_length=100)
    last_name = models.CharField(max_length=100)
    phone = models.CharField(max_length=20, blank=True, null=True)
    date_joined = models.DateTimeField(auto_now_add=True)
    
    def __str__(self):
        return f"{self.first_name} {self.last_name} ({self.email})"


class Child(models.Model):
    """Child profile linked to guardian"""
    child_hash = models.CharField(max_length=64, unique=True, db_index=True)
    guardian = models.ForeignKey(Guardian, on_delete=models.CASCADE, related_name='children')
    first_name = models.CharField(max_length=100)
    last_name = models.CharField(max_length=100, blank=True, null=True)
    date_of_birth = models.DateField()
    profile_image = models.ImageField(upload_to='child_profiles/', blank=True, null=True)
    date_joined = models.DateTimeField(auto_now_add=True)
    is_active = models.BooleanField(default=True)
    
    class Meta:
        ordering = ['first_name', 'last_name']
        
    def __str__(self):
        return f"{self.first_name} {self.last_name or ''} ({self.child_hash})"
    
    @property
    def full_name(self):
        if self.last_name:
            return f"{self.first_name} {self.last_name}"
        return self.first_name
    
    @property
    def age(self):
        from datetime import date
        today = date.today()
        return today.year - self.date_of_birth.year - (
            (today.month, today.day) < (self.date_of_birth.month, self.date_of_birth.day)
        )
    
    def save(self, *args, **kwargs):
        if not self.child_hash:
            self.child_hash = secrets.token_urlsafe(16)
        super().save(*args, **kwargs)


class ScreenTime(models.Model):
    """Screen time data from child's device"""
    child = models.ForeignKey(Child, on_delete=models.CASCADE, related_name='screen_times')
    date = models.DateField(db_index=True)
    total_screen_time = models.IntegerField(help_text="Total screen time in seconds")
    app_wise_data = models.JSONField(default=dict, help_text="App usage breakdown by hour")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        ordering = ['-date']
        unique_together = ['child', 'date']
        indexes = [
            models.Index(fields=['child', 'date']),
        ]
        
    def __str__(self):
        return f"{self.child.first_name} - {self.date} - {self.total_screen_time}s"


class Location(models.Model):
    """Location data from child's device"""
    child = models.ForeignKey(Child, on_delete=models.CASCADE, related_name='locations')
    latitude = models.FloatField()
    longitude = models.FloatField()
    timestamp = models.DateTimeField(db_index=True)
    address = models.CharField(max_length=500, blank=True, null=True, help_text="Reverse geocoded address")
    accuracy = models.FloatField(blank=True, null=True, help_text="Location accuracy in meters")
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        ordering = ['-timestamp']
        indexes = [
            models.Index(fields=['child', 'timestamp']),
        ]
        
    def __str__(self):
        return f"{self.child.first_name} - {self.timestamp} - ({self.latitude}, {self.longitude})"


class SiteAccess(models.Model):
    """Website access logs from child's device"""
    child = models.ForeignKey(Child, on_delete=models.CASCADE, related_name='site_accesses')
    url = models.TextField()
    domain = models.CharField(max_length=255, db_index=True)
    timestamp = models.DateTimeField(db_index=True)
    accessed = models.BooleanField(help_text="True if accessed, False if blocked")
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        ordering = ['-timestamp']
        indexes = [
            models.Index(fields=['child', 'timestamp']),
            models.Index(fields=['child', 'accessed']),
        ]
        verbose_name_plural = "Site accesses"
        
    def __str__(self):
        status = "accessed" if self.accessed else "blocked"
        return f"{self.child.first_name} - {self.domain} - {status}"


class AppRestriction(models.Model):
    """App-wise screen time restrictions set by guardian"""
    child = models.ForeignKey(Child, on_delete=models.CASCADE, related_name='app_restrictions')
    package_name = models.CharField(max_length=255, help_text="e.g., com.instagram.android")
    hours_limit = models.FloatField(help_text="Daily limit in hours")
    app_name = models.CharField(max_length=255, blank=True, null=True)
    app_icon_url = models.URLField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        ordering = ['package_name']
        unique_together = ['child', 'package_name']
        
    def __str__(self):
        return f"{self.child.first_name} - {self.package_name} - {self.hours_limit}h"
    
    @property
    def minutes_limit(self):
        return int(self.hours_limit * 60)
