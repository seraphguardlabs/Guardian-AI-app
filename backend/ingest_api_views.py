"""
Guardian AI - Data Ingestion API
Endpoint to receive data from child devices
"""

from django.http import JsonResponse
from django.views.decorators.http import require_http_methods
from django.views.decorators.csrf import csrf_exempt
from django.utils import timezone
from datetime import datetime
import json

from .models import Child, ScreenTime, Location, SiteAccess
from .helpers import extract_domain


@csrf_exempt
@require_http_methods(["POST"])
def ingest_data(request):
    """
    POST /api/ingest/
    Receive data from child devices (screen time, location, site access)
    """
    try:
        data = json.loads(request.body)
    except json.JSONDecodeError:
        return JsonResponse({
            'status': 'error',
            'message': 'Invalid JSON data'
        }, status=400)
    
    # Extract child_hash (can be at root or in each section)
    child_hash = data.get('child_hash')
    
    if not child_hash:
        # Try to get from first available section
        if 'screen_time_info' in data:
            child_hash = data['screen_time_info'].get('child_hash')
        elif 'location_info' in data:
            child_hash = data['location_info'].get('child_hash')
        elif 'site_access_info' in data:
            child_hash = data['site_access_info'].get('child_hash')
    
    if not child_hash:
        return JsonResponse({
            'status': 'error',
            'message': 'child_hash is required'
        }, status=400)
    
    # Get child
    try:
        child = Child.objects.get(child_hash=child_hash, is_active=True)
    except Child.DoesNotExist:
        return JsonResponse({
            'status': 'error',
            'message': 'Invalid child_hash'
        }, status=404)
    
    response_data = {
        'status': 'ok',
        'child_hash': child_hash,
        'processed': []
    }
    
    # Process screen time info
    if 'screen_time_info' in data:
        screen_info = data['screen_time_info']
        
        try:
            date_str = screen_info.get('date')
            if date_str:
                date_obj = datetime.strptime(date_str, '%Y-%m-%d').date()
            else:
                date_obj = datetime.now().date()
            
            total_screen_time = screen_info.get('total_screen_time', 0)
            app_wise_data = screen_info.get('app_wise_data', {})
            
            # Update or create
            screen_time, created = ScreenTime.objects.update_or_create(
                child=child,
                date=date_obj,
                defaults={
                    'total_screen_time': total_screen_time,
                    'app_wise_data': app_wise_data,
                }
            )
            
            response_data['processed'].append('screen_time_info')
        except Exception as e:
            response_data['errors'] = response_data.get('errors', [])
            response_data['errors'].append(f'screen_time_info: {str(e)}')
    
    # Process location info
    if 'location_info' in data:
        location_info = data['location_info']
        
        try:
            timestamp_str = location_info.get('timestamp')
            if timestamp_str:
                timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
            else:
                timestamp = timezone.now()
            
            latitude = location_info.get('latitude')
            longitude = location_info.get('longitude')
            
            if latitude is not None and longitude is not None:
                Location.objects.create(
                    child=child,
                    latitude=float(latitude),
                    longitude=float(longitude),
                    timestamp=timestamp,
                )
                
                response_data['processed'].append('location_info')
        except Exception as e:
            response_data['errors'] = response_data.get('errors', [])
            response_data['errors'].append(f'location_info: {str(e)}')
    
    # Process site access info
    if 'site_access_info' in data:
        site_info = data['site_access_info']
        
        try:
            logs = site_info.get('logs', [])
            
            for log_entry in logs:
                timestamp_str = log_entry.get('timestamp')
                if timestamp_str:
                    timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                else:
                    timestamp = timezone.now()
                
                url = log_entry.get('url', '')
                accessed = log_entry.get('accessed', True)
                
                domain = extract_domain(url)
                
                SiteAccess.objects.create(
                    child=child,
                    url=url,
                    domain=domain,
                    timestamp=timestamp,
                    accessed=accessed,
                )
            
            response_data['processed'].append(f'site_access_info ({len(logs)} logs)')
        except Exception as e:
            response_data['errors'] = response_data.get('errors', [])
            response_data['errors'].append(f'site_access_info: {str(e)}')
    
    if not response_data['processed']:
        return JsonResponse({
            'status': 'error',
            'message': 'No valid data sections found'
        }, status=400)
    
    return JsonResponse(response_data)
