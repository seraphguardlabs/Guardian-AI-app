# 📍 EXACT LOCATION: Risk Alerts Section on Parent Dashboard

## Visual Layout of Parent Dashboard Screen

```
┌─────────────────────────────────────────────────────┐
│                  PARENT DASHBOARD                   │
├─────────────────────────────────────────────────────┤
│                                                     │
│  [HEADER]                                           │
│  Child's Dashboard  📍 Location Status              │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │  METRICS SECTION (with carousel swipe)        │ │
│  │  • Top Apps Today                             │ │
│  │  • Risk Signals                               │ │
│  │  • Active Alerts                              │ │
│  │  • Well-being Score                           │ │
│  │  • Child Certificates                         │ │
│  │  [dots indicator for 5 cards]                 │ │
│  └───────────────────────────────────────────────┘ │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │  PENDING REQUESTS SECTION                     │ │
│  │  "3 pending" badge                            │ │
│  │  • Time extension request 1                   │ │
│  │  • Time extension request 2                   │ │
│  │  • Time extension request 3                   │ │
│  └───────────────────────────────────────────────┘ │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │  SCREEN TIME CARD                             │ │
│  │  [Line chart with data]                       │ │
│  └───────────────────────────────────────────────┘ │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │  APP USAGE CARD                               │ │
│  │  [App usage data]                             │ │
│  └───────────────────────────────────────────────┘ │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │  LOCATIONS CARD                               │ │
│  │  [GPS location data]                          │ │
│  └───────────────────────────────────────────────┘ │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │  SITE ACCESS CARD                             │ │
│  │  [Website access logs]                        │ │
│  └───────────────────────────────────────────────┘ │
│                                                     │
│  ⬇️ SCROLL DOWN ⬇️ TO SEE THIS:                   │
│                                                     │
│  ┌───────────────────────────────────────────────┐ │
│  │  🔴 RISK ALERTS SECTION  ← ← ← YOU ARE HERE   │ │
│  │  ┌─────────────────────────────────────────┐ │ │
│  │  │ Total Alerts: 5                         │ │ │
│  │  ├─────────────────────────────────────────┤ │ │
│  │  │ 🔴 HIGH RISK (78/100)                   │ │ │
│  │  │ "Detected grooming language"            │ │ │
│  │  │ John Smith • 5 minutes ago              │ │ │
│  │  ├─────────────────────────────────────────┤ │ │
│  │  │ 🟠 MEDIUM RISK (45/100)                 │ │ │
│  │  │ "Unusual app activity"                  │ │ │
│  │  │ John Smith • 12 minutes ago             │ │ │
│  │  ├─────────────────────────────────────────┤ │ │
│  │  │ 🔴 HIGH RISK (82/100)                   │ │ │
│  │  │ "Solicitation detected"                 │ │ │
│  │  │ John Smith • 18 minutes ago             │ │ │
│  │  ├─────────────────────────────────────────┤ │ │
│  │  │ 🟢 LOW RISK (15/100)                    │ │ │
│  │  │ "High screen time alert"                │ │ │
│  │  │ John Smith • 25 minutes ago             │ │ │
│  │  ├─────────────────────────────────────────┤ │ │
│  │  │ 🟠 MEDIUM RISK (52/100)                 │ │ │
│  │  │ "Unknown contact interaction"           │ │ │
│  │  │ John Smith • 32 minutes ago             │ │ │
│  │  └─────────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────────┘ │
│                                                     │
│  [Bottom Navigation Bar]                            │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## 📍 EXACT SCROLL POSITION

### **Scroll Sequence:**

1. **Top of screen** (when app first loads):
   - Header with child name and location status

2. **Scroll down 1** - You see:
   - Metrics section with carousel (5 cards that you can swipe)

3. **Scroll down 2** - You see:
   - Pending Requests section

4. **Scroll down 3** - You see:
   - Screen Time card

5. **Scroll down 4** - You see:
   - App Usage card

6. **Scroll down 5** - You see:
   - Locations/Map card

7. **Scroll down 6** - You see:
   - Site Access card

8. **Scroll down 7** - ⬇️ **RISK ALERTS SECTION APPEARS** ⬇️

---

## 📌 EXACTLY WHERE IT IS

### **In Code Order (Line Numbers):**

```
Line 1074: _buildMetricsSection()         ← Metrics carousel
Line 1079: _buildPendingRequestsSection() ← Pending requests
Line 1084: _buildScreenTimeCard()         ← Screen time
Line 1087: _buildAppUsageCard()           ← App usage
Line 1090: _buildLocationsCard()          ← Locations
Line 1093: _buildSiteAccessCard()         ← Site access

Line 1096: _buildRiskAlertsFullSection()  ← ⬅️ RISK ALERTS (LAST)
```

### **Display Condition:**

```dart
if (_activeAlerts.isNotEmpty) _buildRiskAlertsFullSection(),
```

**Meaning:** Risk Alerts section **only shows if there are alerts to display**

---

## 🎯 How to Find It While Testing

### **Step 1: Launch App as Parent**
```
✓ Login as parent
✓ Select a child
```

### **Step 2: Scroll to the Bottom**
```
✓ Full screen scrolls vertically
✓ Scroll past all data cards
✓ Keep scrolling down...
```

### **Step 3: You'll See**
```
RED/PINK CARD labeled "RISK ALERTS"
With list of recent alerts showing:
- Severity badge (🔴🟠🟢)
- Risk score (0-100%)
- Alert summary
- Time ago (5m, 12m, etc.)
- Child name
```

### **Step 4: Interact**
```
✓ Tap any alert to see full details
✓ Details show timestamp, risk score, full content
✓ Parent can take actions (WARN, BLOCK_APP, BLOCK_CONTACT)
```

---

## 🔴 VISUAL MARKERS TO LOOK FOR

**The Risk Alerts section has:**

| Visual Element | Color | What It Means |
|---|---|---|
| Header text | White | "RISK ALERTS" title |
| Background | Dark (0xFF1A1A1A) | Card background |
| Severity HIGH | 🔴 Red (#FF4C4C) | Critical risk |
| Severity MEDIUM | 🟠 Orange (#FFA500) | Medium risk |
| Severity LOW | 🟢 Blue (#2B4C8F) | Low risk |
| Risk Score | White text | 0-100 percentage |
| Time | White70 | How long ago |

---

## 📋 COMPLETE VERTICAL LAYOUT

```
TOP ▲

     ┌─ Header (Dashboard title)
     │
     ├─ Metrics Carousel
     │  (5 cards you can swipe)
     │
     ├─ Pending Requests
     │  (Time extensions)
     │
     ├─ Screen Time Card
     │  (Line chart)
     │
     ├─ App Usage Card
     │  (Top apps)
     │
     ├─ Locations Card
     │  (GPS map)
     │
     ├─ Site Access Card
     │  (Website logs)
     │
     ⬇️ SCROLL TO BOTTOM ⬇️
     │
     └─ RISK ALERTS SECTION ← ← ← HERE!
        (Real alerts with severity badges)

BOTTOM ▼
```

---

## ✅ HOW TO VERIFY IT'S WORKING

### **When Testing:**

1. ✅ **Open app as Parent**
   
2. ✅ **Select a child account**
   
3. ✅ **Scroll down to the very bottom** (past all data cards)
   
4. ✅ **Look for RED/PINK card labeled "RISK ALERTS"**
   
5. ✅ **You should see:**
   - Alert count (e.g., "5 alerts")
   - Top 5 recent alerts in list
   - Each with severity badge, score, summary, time
   
6. ✅ **Click an alert:**
   - Should navigate to AlertDetailScreen
   - Show full alert information
   - Display risk score visualization
   - Show parent action buttons

### **If You Don't See It:**
- Make sure there are **alerts in the database**
- Scroll to the **very bottom** of the screen
- Check child device is generating alerts (AI models running)
- Wait 30-60 seconds for background monitoring to run

---

## 🎯 EXACT COORDINATES

```
Screen: Parent Dashboard
Method: build()
Widget: SingleChildScrollView → Column

Position in Column:
├─ Index 0: Header (padding + row)
├─ Index 1: SafeArea
├─ Index 2: Metrics section (if _metrics != null)
├─ Index 3: Pending requests (Consumer)
├─ Index 4: Screen time (if _screenTime != null)
├─ Index 5: App usage (if _appUsage != null)
├─ Index 6: Locations (if _locations != null)
├─ Index 7: Site access (if _siteAccess != null)
├─ Index 8: RISK ALERTS (if _activeAlerts.isNotEmpty) ← HERE!
└─ Index 9: Bottom spacing (SizedBox height: 20)
```

---

## 📱 ON DIFFERENT SCREEN SIZES

The Risk Alerts section will appear:
- ✅ Bottom of screen on small phones (after scrolling)
- ✅ Bottom of screen on tablets (after scrolling)
- ✅ Bottom of screen on landscape (after scrolling)
- ✅ **Always at the same vertical position** - after all other cards

---

**SUMMARY:** Risk Alerts section is at the **BOTTOM** of the Parent Dashboard. **Scroll down past all data cards** to see it. It will show a **RED/PINK card with alert list** when alerts exist.
