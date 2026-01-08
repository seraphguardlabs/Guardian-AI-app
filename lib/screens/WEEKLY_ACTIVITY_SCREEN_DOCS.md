# Weekly Activity Screen Documentation

## Overview

The Weekly Activity Screen displays a child's screen time trends over a 3-week period using an interactive line chart. It provides parents with insights into their child's device usage patterns and helps identify trends.

## File Location
`lib/screens/weekly_activity_screen.dart`

## Features

### 1. Multi-Week Comparison
- Displays up to 3 weeks of screen time data simultaneously
- Current week (bright blue)
- Last week (medium blue)
- Two weeks ago (light blue)
- Conditional rendering: Only shows weeks with actual data

### 2. Today's Usage Summary
- Large display of today's screen time
- Progress bar showing usage vs. daily limit (3 hours)
- Visual indicator when approaching or exceeding limit
- Color-coded legend for all displayed weeks

### 3. Interactive Line Chart
- 7-day view (Monday to Sunday)
- Curved lines for smoother visualization
- Highlighted dot for today's data point
- Touch tooltips showing exact screen time on tap
- Dynamic Y-axis scaling based on actual data
- Y-axis labels showing hours
- X-axis labels showing day abbreviations

### 4. Weekly Summary
- Total screen time for each week
- Color-coded indicators matching chart lines
- Easy comparison across weeks

### 5. Pull to Refresh
- Swipe down to reload data from API
- Updates all three weeks simultaneously

## UI Components

### App Bar
- Title: "Weekly Activity"
- Back button to return to parent dashboard
- Dark background (#0F0F0F)

### Today's Usage Card
```
┌─────────────────────────────┐
│ Today                       │
│ 2h 30m                      │
│ ▓▓▓▓▓░░░░░░░ (83% of limit) │
│ ● This Week  ● Last Week    │
└─────────────────────────────┘
```

### Chart Card
```
┌─────────────────────────────┐
│ 5h │                         │
│ 4h │     ●                   │
│ 3h │   ●   ●   ●             │
│ 2h │ ●           ●           │
│ 1h │               ●     ●   │
│ 0h └─────────────────────────│
│    MON TUE WED THU FRI SAT SUN│
└─────────────────────────────┘
```

### Weekly Summary Card
```
┌─────────────────────────────┐
│ Weekly Summary              │
│ ▌This Week      12h 30m     │
│ ▌Last Week      15h 45m     │
│ ▌Two Weeks Ago  10h 20m     │
└─────────────────────────────┘
```

## API Integration

### Endpoint
`GET /api/mobile/child/<child_hash>/screen-time/`

### Authentication
- Header-based authentication using parent credentials
- `X-Email`: Parent's email
- `X-Password`: Parent's password

### Query Parameters
- `start_date`: Start of week (Monday, format: YYYY-MM-DD)
- `end_date`: End of week (Sunday, format: YYYY-MM-DD)

### Request Example
```
GET /api/mobile/child/abc123/screen-time/?start_date=2026-01-06&end_date=2026-01-12
Headers:
  X-Email: parent@example.com
  X-Password: secretpass
```

### Response Format
```json
{
  "status": "ok",
  "child_hash": "abc123",
  "child_name": "Emma Smith",
  "trend": [
    {
      "date": "2026-01-06",
      "total_seconds": 9000,
      "formatted": "2h 30m",
      "app_count": 5
    },
    {
      "date": "2026-01-07",
      "total_seconds": 10800,
      "formatted": "3h 0m",
      "app_count": 8
    }
  ],
  "summary": {
    "total_seconds": 86400,
    "average_seconds": 12343
  }
}
```

### Data Flow
1. Screen initializes → Calls `_fetchWeeklyData()`
2. Calculates 3 week date ranges (Monday to Sunday)
3. Makes 3 parallel API calls using `Future.wait()`
4. Processes responses with `_processWeekData()`
5. Converts seconds to hours for chart rendering
6. Updates UI state with new data

## Key Methods

### Data Fetching
- `_fetchWeeklyData()`: Main data fetching method, called on init and refresh
- `_processWeekData()`: Converts API response to Map<String, double>

### Data Processing
- `_getWeekSpots()`: Converts week data to FlSpot list for chart
- `_calculateMaxY()`: Dynamically calculates Y-axis maximum
- `_calculateWeekTotal()`: Sums total hours for a week
- `_hasWeekData()`: Checks if week has non-zero data

### Formatting
- `_formatDuration()`: Converts hours (2.5) to "2h 30m" format

### Widget Builders
- `_buildLegendItem()`: Creates colored circle with label
- `_buildStatRow()`: Creates weekly summary row

## State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `_loading` | bool | Loading state indicator |
| `_selectedPeriod` | String | Currently selected time period (future feature) |
| `_currentWeekData` | Map<String, double> | Current week's daily screen time |
| `_previousWeekData` | Map<String, double> | Last week's daily screen time |
| `_twoWeeksAgoData` | Map<String, double> | Two weeks ago daily screen time |
| `_todayUsage` | double | Today's screen time in hours |

## Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `_dailyLimitHours` | 3.0 | Daily screen time limit in hours |

## Color Scheme

| Element | Color Code | Usage |
|---------|------------|-------|
| Background | #0F0F0F | Main background |
| Card Background | #1A1A1A | All cards and containers |
| Current Week Line | #2196F3 | Bright blue for current week |
| Last Week Line | #64B5F6 | Medium blue for last week |
| Two Weeks Ago Line | #90CAF9 | Light blue for two weeks ago |
| Progress Bar | #2196F3 → #1976D2 | Blue gradient |
| Text Primary | #FFFFFF | Main text |
| Text Secondary | #FFFFFF70 | Labels and secondary text |

## Chart Configuration

### Line Chart Settings
- Height: 250px
- X-axis: 0-6 (Monday to Sunday)
- Y-axis: 0 to calculated max (dynamic)
- Grid: Horizontal lines every 1 hour
- Line width: 3-4px
- Curved lines: Yes
- Dots: Only shown for today on current week

### Touch Behavior
- Enabled: Yes
- Tooltip: Shows formatted duration
- Tooltip background: #5B4A9F (purple)

## Error Handling

### Missing Credentials
- Logs warning if parent email/password is missing
- Stops loading and returns early

### API Failures
- Catches and logs errors
- Sets loading to false
- Empty data maps prevent crashes

### Null Safety
- All API data safely unwrapped with null checks
- Default values (0.0) for missing data
- Conditional rendering prevents errors with empty data

## Performance Optimizations

1. **Parallel API Calls**: Uses `Future.wait()` to fetch all 3 weeks simultaneously
2. **Conditional Rendering**: Only renders weeks with data
3. **Efficient State Updates**: Only updates state when mounted
4. **Data Caching**: Data persists until manual refresh

## Future Enhancements

### Potential Features
1. **Time Period Selector**: Dropdown to select different time ranges
2. **Daily Limit Configuration**: Allow parents to set custom limits
3. **Export Data**: Download chart as image or export CSV
4. **Comparison View**: Side-by-side comparison of different time periods
5. **Trend Indicators**: Show increase/decrease percentages
6. **App Breakdown**: Tap a day to see app-wise usage
7. **Notifications**: Alert when child exceeds limit
8. **Goals**: Set and track screen time reduction goals

## Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  fl_chart: ^0.63.0  # For line charts
  intl: ^0.18.1      # For date formatting
  provider: ^6.0.5   # For state management
```

## Testing Checklist

- [ ] Chart displays correctly with 1 week of data
- [ ] Chart displays correctly with 2 weeks of data
- [ ] Chart displays correctly with 3 weeks of data
- [ ] Chart handles weeks with no data
- [ ] Today's usage shows correct value
- [ ] Progress bar fills correctly
- [ ] Y-axis scales properly with different data ranges
- [ ] Touch tooltips work on all data points
- [ ] Pull to refresh updates data
- [ ] Back button returns to parent dashboard
- [ ] Loading state displays correctly
- [ ] Error states handled gracefully
- [ ] Works with different screen sizes
- [ ] Legend only shows weeks with data
- [ ] Weekly summary totals are accurate

## Usage Example

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => WeeklyActivityScreen(
      child: selectedChild,
    ),
  ),
);
```

## Related Files

- `lib/services/api_service.dart`: Contains `fetchScreenTime()` method
- `lib/models/child.dart`: Child data model
- `lib/utils/preferences_manager.dart`: Stores parent credentials
- `lib/screens/parent_dashboard_screen.dart`: Navigates to this screen

## Accessibility

- Semantic labels on interactive elements
- Color contrast meets WCAG AA standards
- Touch targets are at least 44x44 points
- Screen reader compatible

## Troubleshooting

### Chart shows no data
- Check API response in debug logs
- Verify date range calculations
- Ensure child hash is correct
- Check parent credentials are stored

### Y-axis too small/large
- Check `_calculateMaxY()` logic
- Verify data values are in hours (not seconds)

### Today's dot not highlighted
- Verify `now.weekday - 1` calculation
- Check if today's data exists in current week

### Pull to refresh not working
- Ensure `AlwaysScrollableScrollPhysics` is set
- Check `_fetchWeeklyData()` is called

## Version History

- v1.0.0 (2026-01-08): Initial implementation
  - 3-week comparison chart
  - Today's usage summary
  - Weekly totals
  - Pull to refresh
  - Dynamic Y-axis scaling
  - API integration
