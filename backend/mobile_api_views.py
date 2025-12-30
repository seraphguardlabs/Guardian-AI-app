"""
Guardian AI - Mobile API Views
API endpoints for parent mobile app dashboard
"""

from django.http import JsonResponse
from django.views.decorators.http import require_http_methods
from django.views.decorators.csrf import csrf_exempt
from django.db.models import Sum, Count, Q, Max, Min, Avg
from django.utils import timezone
from datetime import datetime, timedelta, date
from decimal import Decimal
import json

from .models import Guardian, Child, ScreenTime, Location, SiteAccess, AppRestriction
from .helpers import authenticate_guardian, parse_date_range, format_time_seconds


@csrf_exempt
@require_http_methods(["GET"])
def children_list(request):
    """
    GET /api/mobile/children/
    Retrieve all children registered under the authenticated guardian
    """
    # Authenticate
    guardian = authenticate_guardian(request)
    if not guardian:
        return JsonResponse({
            'status': 'error',
            'message': 'Authentication required. Provide X-Email and X-Password headers.'
        }, status=401)
    
    # Get all children for this guardian
    children = Child.objects.filter(guardian=guardian, is_active=True)
    
    children_data = []
    for child in children:
        children_data.append({
            'child_hash': child.child_hash,
            'first_name': child.first_name,
            'last_name': child.last_name or '',
            'full_name': child.full_name,
            'date_of_birth': child.date_of_birth.isoformat(),
            'age': child.age,
            'profile_image_url': request.build_absolute_uri(child.profile_image.url) if child.profile_image else None,
            'date_joined': child.date_joined.isoformat(),
        })
    
    return JsonResponse({
        'status': 'ok',
        'count': len(children_data),
        'children': children_data,
    })


@csrf_exempt
@require_http_methods(["GET"])
def child_metrics(request, child_hash):
    """
    GET /api/mobile/child/<child_hash>/metrics/
    Get aggregated metrics for a specific child
    """
    # Authenticate
    guardian = authenticate_guardian(request)
    if not guardian:
        return JsonResponse({
            'status': 'error',
            'message': 'Authentication required. Provide X-Email and X-Password headers.'
        }, status=401)
    
    # Get child
    try:
        child = Child.objects.get(child_hash=child_hash, guardian=guardian, is_active=True)
    except Child.DoesNotExist:
        return JsonResponse({
            'status': 'error',
            'message': 'Child not found or you do not have access'
        }, status=404)
    
    # Parse date range (default: last 30 days)
    start_date, end_date = parse_date_range(
        request.GET.get('start_date'),
        request.GET.get('end_date'),
        default_days=30
    )
    
    days_diff = (end_date - start_date).days + 1
    
    # Screen time metrics
    screen_times = ScreenTime.objects.filter(
        child=child,
        date__gte=start_date,
        date__lte=end_date
    )
    
    total_screen_time = screen_times.aggregate(Sum('total_screen_time'))['total_screen_time__sum'] or 0
    daily_average = total_screen_time // days_diff if days_diff > 0 else 0
    
    # Count unique apps
    unique_apps = set()
    for st in screen_times:
        unique_apps.update(st.app_wise_data.keys())
    
    # Latest location
    latest_location = Location.objects.filter(child=child).first()
    location_data = None
    if latest_location:
        location_data = {
            'latitude': latest_location.latitude,
            'longitude': latest_location.longitude,
            'timestamp': latest_location.timestamp.isoformat(),
            'address': latest_location.address,
        }
    
    # Site access stats
    site_accesses = SiteAccess.objects.filter(
        child=child,
        timestamp__gte=timezone.make_aware(datetime.combine(start_date, datetime.min.time())),
        timestamp__lte=timezone.make_aware(datetime.combine(end_date, datetime.max.time()))
    )
    
    total_sites = site_accesses.count()
    blocked_sites = site_accesses.filter(accessed=False).count()
    accessed_sites = site_accesses.filter(accessed=True).count()
    
    return JsonResponse({
        'status': 'ok',
        'child_hash': child_hash,
        'child_name': child.full_name,
        'date_range': {
            'start_date': start_date.isoformat(),
            'end_date': end_date.isoformat(),
            'days': days_diff,
        },
        'metrics': {
            'total_screen_time_seconds': total_screen_time,
            'total_screen_time_formatted': format_time_seconds(total_screen_time),
            'daily_average_seconds': daily_average,
            'daily_average_formatted': format_time_seconds(daily_average),
            'unique_apps_used': len(unique_apps),
            'latest_location': location_data,
            'site_access': {
                'total_blocked': blocked_sites,
                'total_accessed': accessed_sites,
                'total': total_sites,
            }
        }
    })


@csrf_exempt
@require_http_methods(["GET"])
def screen_time_trend(request, child_hash):
    """
    GET /api/mobile/child/<child_hash>/screen-time/
    Get detailed daily screen time trend data
    """
    # Authenticate
    guardian = authenticate_guardian(request)
    if not guardian:
        return JsonResponse({
            'status': 'error',
            'message': 'Authentication required. Provide X-Email and X-Password headers.'
        }, status=401)
    
    # Get child
    try:
        child = Child.objects.get(child_hash=child_hash, guardian=guardian, is_active=True)
    except Child.DoesNotExist:
        return JsonResponse({
            'status': 'error',
            'message': 'Child not found'
        }, status=404)
    
    # Parse date range (default: last 30 days)
    start_date, end_date = parse_date_range(
        request.GET.get('start_date'),
        request.GET.get('end_date'),
        default_days=30
    )
    
    # Get screen time data
    screen_times = ScreenTime.objects.filter(
        child=child,
        date__gte=start_date,
        date__lte=end_date
    ).order_by('date')
    
    # Build trend data
    trend = []
    total_seconds = 0
    max_seconds = 0
    max_date = None
    min_seconds = float('inf')
    min_date = None
    
    for st in screen_times:
        app_count = len(st.app_wise_data.keys()) if st.app_wise_data else 0
        trend.append({
            'date': st.date.isoformat(),
            'total_seconds': st.total_screen_time,
            'formatted': format_time_seconds(st.total_screen_time),
            'app_count': app_count,
        })
        
        total_seconds += st.total_screen_time
        if st.total_screen_time > max_seconds:
            max_seconds = st.total_screen_time
            max_date = st.date.isoformat()
        if st.total_screen_time < min_seconds:
            min_seconds = st.total_screen_time
            min_date = st.date.isoformat()
    
    days_with_data = len(trend)
    average_seconds = total_seconds // days_with_data if days_with_data > 0 else 0
    
    if min_seconds == float('inf'):
        min_seconds = 0
    
    return JsonResponse({
        'status': 'ok',
        'child_hash': child_hash,
        'child_name': child.full_name,
        'date_range': {
            'start_date': start_date.isoformat(),
            'end_date': end_date.isoformat(),
        },
        'trend': trend,
        'summary': {
            'total_seconds': total_seconds,
            'total_formatted': format_time_seconds(total_seconds),
            'average_seconds': average_seconds,
            'average_formatted': format_time_seconds(average_seconds),
            'max_seconds': max_seconds,
            'max_formatted': format_time_seconds(max_seconds),
            'max_date': max_date,
            'min_seconds': min_seconds,
            'min_formatted': format_time_seconds(min_seconds),
            'min_date': min_date,
            'days_with_data': days_with_data,
        }
    })


@csrf_exempt
@require_http_methods(["GET"])
def app_usage_data(request, child_hash):
    """
    GET /api/mobile/child/<child_hash>/app-usage/
    Get detailed breakdown of app usage
    """
    # Authenticate
    guardian = authenticate_guardian(request)
    if not guardian:
        return JsonResponse({
            'status': 'error',
            'message': 'Authentication required. Provide X-Email and X-Password headers.'
        }, status=401)
    
    # Get child
    try:
        child = Child.objects.get(child_hash=child_hash, guardian=guardian, is_active=True)
    except Child.DoesNotExist:
        return JsonResponse({
            'status': 'error',
            'message': 'Child not found'
        }, status=404)
    
    # Parse date range (default: last 30 days)
    start_date, end_date = parse_date_range(
        request.GET.get('start_date'),
        request.GET.get('end_date'),
        default_days=30
    )
    
    days_diff = (end_date - start_date).days + 1
    
    # Get screen time data
    screen_times = ScreenTime.objects.filter(
        child=child,
        date__gte=start_date,
        date__lte=end_date
    )
    
    # Aggregate app usage
    app_totals = {}
    for st in screen_times:
        for package, hours_data in st.app_wise_data.items():
            if package not in app_totals:
                app_totals[package] = 0
            # Sum all hours for this app
            for hour, seconds in hours_data.items():
                app_totals[package] += seconds
    
    # Calculate total and percentages
    total_seconds = sum(app_totals.values())
    
    # Build app list with details
    apps = []
    for package, seconds in sorted(app_totals.items(), key=lambda x: x[1], reverse=True):
        percentage = (seconds / total_seconds * 100) if total_seconds > 0 else 0
        daily_avg = seconds // days_diff if days_diff > 0 else 0
        
        apps.append({
            'domain': package,
            'name': package.split('.')[-1].title(),  # Simple name extraction
            'icon_url': f"https://play-lh.googleusercontent.com/{package}",  # Placeholder
            'total_seconds': seconds,
            'formatted': format_time_seconds(seconds),
            'percentage': round(percentage, 1),
            'daily_average_seconds': daily_avg,
            'daily_average_formatted': format_time_seconds(daily_avg),
        })
    
    # Get most used app
    most_used = None
    if apps:
        most_used = {
            'domain': apps[0]['domain'],
            'name': apps[0]['name'],
            'seconds': apps[0]['total_seconds'],
            'formatted': apps[0]['formatted'],
        }
    
    return JsonResponse({
        'status': 'ok',
        'child_hash': child_hash,
        'child_name': child.full_name,
        'date_range': {
            'start_date': start_date.isoformat(),
            'end_date': end_date.isoformat(),
            'days': days_diff,
        },
        'apps': apps,
        'summary': {
            'total_seconds': total_seconds,
            'total_formatted': format_time_seconds(total_seconds),
            'app_count': len(apps),
            'most_used_app': most_used,
        }
    })


@csrf_exempt
@require_http_methods(["GET"])
def location_history(request, child_hash):
    """
    GET /api/mobile/child/<child_hash>/locations/
    Get location history data
    """
    # Authenticate
    guardian = authenticate_guardian(request)
    if not guardian:
        return JsonResponse({
            'status': 'error',
            'message': 'Authentication required. Provide X-Email and X-Password headers.'
        }, status=401)
    
    # Get child
    try:
        child = Child.objects.get(child_hash=child_hash, guardian=guardian, is_active=True)
    except Child.DoesNotExist:
        return JsonResponse({
            'status': 'error',
            'message': 'Child not found'
        }, status=404)
    
    # Parse date range (default: last 7 days)
    start_date, end_date = parse_date_range(
        request.GET.get('start_date'),
        request.GET.get('end_date'),
        default_days=7
    )
    
    # Get limit (default: 100, max: 500)
    try:
        limit = min(int(request.GET.get('limit', 100)), 500)
    except ValueError:
        limit = 100
    
    # Get locations
    start_datetime = timezone.make_aware(datetime.combine(start_date, datetime.min.time()))
    end_datetime = timezone.make_aware(datetime.combine(end_date, datetime.max.time()))
    
    all_locations = Location.objects.filter(
        child=child,
        timestamp__gte=start_datetime,
        timestamp__lte=end_datetime
    )
    
    total_count = all_locations.count()
    locations = all_locations[:limit]
    
    # Count unique locations (simplified - based on rounded coordinates)
    unique_coords = set()
    for loc in all_locations:
        unique_coords.add((round(loc.latitude, 4), round(loc.longitude, 4)))
    
    locations_data = []
    for loc in locations:
        locations_data.append({
            'latitude': loc.latitude,
            'longitude': loc.longitude,
            'timestamp': loc.timestamp.isoformat(),
        })
    
    return JsonResponse({
        'status': 'ok',
        'child_hash': child_hash,
        'child_name': child.full_name,
        'date_range': {
            'start_date': start_date.isoformat(),
            'end_date': end_date.isoformat(),
        },
        'locations': locations_data,
        'summary': {
            'total_count': total_count,
            'returned_count': len(locations_data),
            'unique_locations': len(unique_coords),
            'limit_applied': limit,
        }
    })


@csrf_exempt
@require_http_methods(["GET"])
def site_access_logs(request, child_hash):
    """
    GET /api/mobile/child/<child_hash>/site-access/
    Get website access logs
    """
    # Authenticate
    guardian = authenticate_guardian(request)
    if not guardian:
        return JsonResponse({
            'status': 'error',
            'message': 'Authentication required. Provide X-Email and X-Password headers.'
        }, status=401)
    
    # Get child
    try:
        child = Child.objects.get(child_hash=child_hash, guardian=guardian, is_active=True)
    except Child.DoesNotExist:
        return JsonResponse({
            'status': 'error',
            'message': 'Child not found'
        }, status=404)
    
    # Parse date range (default: last 7 days)
    start_date, end_date = parse_date_range(
        request.GET.get('start_date'),
        request.GET.get('end_date'),
        default_days=7
    )
    
    # Get filter (all, accessed, blocked)
    filter_type = request.GET.get('filter', 'all')
    
    # Get limit (default: 100, max: 500)
    try:
        limit = min(int(request.GET.get('limit', 100)), 500)
    except ValueError:
        limit = 100
    
    # Get site access logs
    start_datetime = timezone.make_aware(datetime.combine(start_date, datetime.min.time()))
    end_datetime = timezone.make_aware(datetime.combine(end_date, datetime.max.time()))
    
    logs_query = SiteAccess.objects.filter(
        child=child,
        timestamp__gte=start_datetime,
        timestamp__lte=end_datetime
    )
    
    # Apply filter
    if filter_type == 'blocked':
        logs_query = logs_query.filter(accessed=False)
    elif filter_type == 'accessed':
        logs_query = logs_query.filter(accessed=True)
    
    # Get counts
    total_count = SiteAccess.objects.filter(
        child=child,
        timestamp__gte=start_datetime,
        timestamp__lte=end_datetime
    ).count()
    
    blocked_count = SiteAccess.objects.filter(
        child=child,
        timestamp__gte=start_datetime,
        timestamp__lte=end_datetime,
        accessed=False
    ).count()
    
    accessed_count = SiteAccess.objects.filter(
        child=child,
        timestamp__gte=start_datetime,
        timestamp__lte=end_datetime,
        accessed=True
    ).count()
    
    # Get unique domains
    unique_domains = logs_query.values('domain').distinct().count()
    
    # Get limited logs
    logs = logs_query[:limit]
    
    logs_data = []
    for log in logs:
        logs_data.append({
            'url': log.url,
            'domain': log.domain,
            'timestamp': log.timestamp.isoformat(),
            'accessed': log.accessed,
            'status': 'accessed' if log.accessed else 'blocked',
        })
    
    return JsonResponse({
        'status': 'ok',
        'child_hash': child_hash,
        'child_name': child.full_name,
        'date_range': {
            'start_date': start_date.isoformat(),
            'end_date': end_date.isoformat(),
        },
        'filter_applied': filter_type,
        'logs': logs_data,
        'summary': {
            'total_count': total_count,
            'blocked_count': blocked_count,
            'accessed_count': accessed_count,
            'returned_count': len(logs_data),
            'unique_domains': unique_domains,
            'limit_applied': limit,
        }
    })


@csrf_exempt
@require_http_methods(["GET", "POST"])
def restricted_apps(request, child_hash):
    """
    GET/POST /api/mobile/child/<child_hash>/restricted-apps/
    Get or update app restrictions
    """
    # Authenticate
    guardian = authenticate_guardian(request)
    if not guardian:
        return JsonResponse({
            'status': 'error',
            'message': 'Authentication required. Provide X-Email and X-Password headers.'
        }, status=401)
    
    # Get child
    try:
        child = Child.objects.get(child_hash=child_hash, guardian=guardian, is_active=True)
    except Child.DoesNotExist:
        return JsonResponse({
            'status': 'error',
            'message': 'Child not found'
        }, status=404)
    
    if request.method == 'GET':
        # Get current restrictions
        restrictions = AppRestriction.objects.filter(child=child)
        
        restricted_apps = {}
        restricted_apps_detailed = []
        
        for restriction in restrictions:
            restricted_apps[restriction.package_name] = restriction.hours_limit
            restricted_apps_detailed.append({
                'package': restriction.package_name,
                'hours_limit': restriction.hours_limit,
                'minutes_limit': restriction.minutes_limit,
                'name': restriction.app_name or restriction.package_name.split('.')[-1].title(),
                'icon_url': restriction.app_icon_url or f"https://play-lh.googleusercontent.com/{restriction.package_name}",
            })
        
        return JsonResponse({
            'status': 'ok',
            'child_hash': child_hash,
            'child_name': child.full_name,
            'restricted_apps': restricted_apps,
            'restricted_apps_detailed': restricted_apps_detailed,
            'total_restricted': len(restricted_apps),
        })
    
    elif request.method == 'POST':
        # Update restrictions
        try:
            data = json.loads(request.body)
        except json.JSONDecodeError:
            return JsonResponse({
                'status': 'error',
                'message': 'Invalid JSON data'
            }, status=400)
        
        # Check for action-based update
        action = data.get('action')
        
        if action == 'add':
            # Add a single app restriction
            package = data.get('package')
            hours = data.get('hours')
            
            if not package or hours is None:
                return JsonResponse({
                    'status': 'error',
                    'message': 'Missing package or hours parameter'
                }, status=400)
            
            restriction, created = AppRestriction.objects.update_or_create(
                child=child,
                package_name=package,
                defaults={'hours_limit': float(hours)}
            )
            
            # Get all restrictions
            all_restrictions = AppRestriction.objects.filter(child=child)
            restricted_apps = {r.package_name: r.hours_limit for r in all_restrictions}
            
            return JsonResponse({
                'status': 'ok',
                'message': f"App {package} restricted to {hours} hours/day",
                'child_hash': child_hash,
                'restricted_apps': restricted_apps,
                'total_restricted': len(restricted_apps),
            })
        
        elif action == 'update':
            # Update existing restriction
            package = data.get('package')
            hours = data.get('hours')
            
            if not package or hours is None:
                return JsonResponse({
                    'status': 'error',
                    'message': 'Missing package or hours parameter'
                }, status=400)
            
            try:
                restriction = AppRestriction.objects.get(child=child, package_name=package)
                restriction.hours_limit = float(hours)
                restriction.save()
                
                # Get all restrictions
                all_restrictions = AppRestriction.objects.filter(child=child)
                restricted_apps = {r.package_name: r.hours_limit for r in all_restrictions}
                
                return JsonResponse({
                    'status': 'ok',
                    'message': f"App {package} limit updated to {hours} hours/day",
                    'child_hash': child_hash,
                    'restricted_apps': restricted_apps,
                    'total_restricted': len(restricted_apps),
                })
            except AppRestriction.DoesNotExist:
                return JsonResponse({
                    'status': 'error',
                    'message': f"No restriction found for {package}"
                }, status=404)
        
        elif action == 'remove':
            # Remove restriction
            package = data.get('package')
            
            if not package:
                return JsonResponse({
                    'status': 'error',
                    'message': 'Missing package parameter'
                }, status=400)
            
            deleted_count, _ = AppRestriction.objects.filter(child=child, package_name=package).delete()
            
            if deleted_count == 0:
                return JsonResponse({
                    'status': 'error',
                    'message': f"No restriction found for {package}"
                }, status=404)
            
            # Get remaining restrictions
            all_restrictions = AppRestriction.objects.filter(child=child)
            restricted_apps = {r.package_name: r.hours_limit for r in all_restrictions}
            
            return JsonResponse({
                'status': 'ok',
                'message': f"App {package} restriction removed",
                'child_hash': child_hash,
                'restricted_apps': restricted_apps,
                'total_restricted': len(restricted_apps),
            })
        
        else:
            # Full replacement - set all restrictions at once
            restricted_apps_data = data.get('restricted_apps', {})
            
            # Delete all existing restrictions
            AppRestriction.objects.filter(child=child).delete()
            
            # Create new restrictions
            for package, hours in restricted_apps_data.items():
                AppRestriction.objects.create(
                    child=child,
                    package_name=package,
                    hours_limit=float(hours)
                )
            
            return JsonResponse({
                'status': 'ok',
                'message': 'Restricted apps updated successfully',
                'child_hash': child_hash,
                'restricted_apps': restricted_apps_data,
                'total_restricted': len(restricted_apps_data),
            })


@csrf_exempt
@require_http_methods(["POST"])
def guardian_public_key_update(request):
    """
    POST /api/mobile/guardian/public-key/
    Upload/update guardian's RSA public key
    """
    # Authenticate
    guardian = authenticate_guardian(request)
    if not guardian:
        return JsonResponse({
            'status': 'error',
            'message': 'Authentication required. Provide X-Email and X-Password headers.'
        }, status=401)
    
    # Parse request body
    try:
        data = json.loads(request.body)
    except json.JSONDecodeError:
        return JsonResponse({
            'status': 'error',
            'message': 'Invalid JSON data'
        }, status=400)
    
    # Get public key from request
    public_key = data.get('public_key')
    
    if not public_key:
        return JsonResponse({
            'status': 'error',
            'message': 'Missing public_key parameter'
        }, status=400)
    
    # Validate PEM format (basic check)
    if not public_key.startswith('-----BEGIN PUBLIC KEY-----'):
        return JsonResponse({
            'status': 'error',
            'message': 'Invalid public key format. Must be PEM format.'
        }, status=400)
    
    # Update guardian's public key
    guardian.public_key = public_key
    guardian.save()
    
    return JsonResponse({
        'status': 'ok',
        'message': 'Public key uploaded successfully',
        'guardian_id': guardian.id,
        'email': guardian.email,
        'key_length': len(public_key),
    })


@csrf_exempt
@require_http_methods(["POST"])
def child_public_key_update(request, child_hash):
    """
    POST /api/mobile/child/<child_hash>/public-key/
    Upload/update child's RSA public key
    """
    # Authenticate
    guardian = authenticate_guardian(request)
    if not guardian:
        return JsonResponse({
            'status': 'error',
            'message': 'Authentication required. Provide X-Email and X-Password headers.'
        }, status=401)
    
    # Get child
    try:
        child = Child.objects.get(child_hash=child_hash, guardian=guardian, is_active=True)
    except Child.DoesNotExist:
        return JsonResponse({
            'status': 'error',
            'message': 'Child not found or you do not have access'
        }, status=404)
    
    # Parse request body
    try:
        data = json.loads(request.body)
    except json.JSONDecodeError:
        return JsonResponse({
            'status': 'error',
            'message': 'Invalid JSON data'
        }, status=400)
    
    # Get public key from request
    public_key = data.get('public_key')
    
    if not public_key:
        return JsonResponse({
            'status': 'error',
            'message': 'Missing public_key parameter'
        }, status=400)
    
    # Validate PEM format (basic check)
    if not public_key.startswith('-----BEGIN PUBLIC KEY-----'):
        return JsonResponse({
            'status': 'error',
            'message': 'Invalid public key format. Must be PEM format.'
        }, status=400)
    
    # Update child's public key
    child.public_key = public_key
    child.save()
    
    return JsonResponse({
        'status': 'ok',
        'message': 'Public key uploaded successfully',
        'child_hash': child_hash,
        'child_name': child.full_name,
        'key_length': len(public_key),
    })
