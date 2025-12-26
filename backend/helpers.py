"""
Guardian AI - Authentication and Helper Functions
Utility functions for mobile API endpoints
"""

from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from datetime import datetime, date, timedelta
from .models import Guardian


def authenticate_guardian(request):
    """
    Authenticate guardian using X-Email and X-Password headers
    Returns Guardian object if authenticated, None otherwise
    """
    email = request.headers.get('X-Email')
    password = request.headers.get('X-Password')
    
    if not email or not password:
        return None
    
    # Try to authenticate
    user = authenticate(username=email, password=password)
    
    if not user:
        # Try email-based lookup
        try:
            guardian = Guardian.objects.get(email=email)
            # Check password
            if guardian.user.check_password(password):
                return guardian
        except Guardian.DoesNotExist:
            return None
        return None
    
    # Get guardian
    try:
        guardian = Guardian.objects.get(user=user)
        return guardian
    except Guardian.DoesNotExist:
        return None


def parse_date_range(start_date_str, end_date_str, default_days=30):
    """
    Parse start and end date strings
    Returns (start_date, end_date) as date objects
    """
    # Parse end date (default: today)
    if end_date_str:
        try:
            end_date = datetime.strptime(end_date_str, '%Y-%m-%d').date()
        except ValueError:
            end_date = date.today()
    else:
        end_date = date.today()
    
    # Parse start date (default: N days ago)
    if start_date_str:
        try:
            start_date = datetime.strptime(start_date_str, '%Y-%m-%d').date()
        except ValueError:
            start_date = end_date - timedelta(days=default_days)
    else:
        start_date = end_date - timedelta(days=default_days)
    
    return start_date, end_date


def format_time_seconds(seconds):
    """
    Format seconds into human-readable time string
    Returns: "Xh Ym" or "Xm"
    """
    if seconds < 0:
        seconds = 0
    
    hours = seconds // 3600
    minutes = (seconds % 3600) // 60
    
    if hours > 0:
        return f"{hours}h {minutes}m"
    else:
        return f"{minutes}m"


def extract_domain(url):
    """
    Extract domain from URL
    """
    from urllib.parse import urlparse
    
    try:
        parsed = urlparse(url)
        domain = parsed.netloc or parsed.path
        # Remove www.
        if domain.startswith('www.'):
            domain = domain[4:]
        return domain
    except:
        return url
