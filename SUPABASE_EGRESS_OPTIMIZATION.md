# Supabase Egress Optimization Analysis & Recommendations

## Executive Summary

The Conquer Club Flutter app is already well-optimized in many areas (member-scoped Realtime, pagination on key lists, RPC usage, batched step sync). However, there are **three high-impact fixes** that will meaningfully reduce Supabase egress with minimal code changes:

1. **Search debouncing** (immediate, ~5–10 min)
2. **Unbounded list reads** (easy caps, ~15 min)
3. **Global Realtime fan-out for coaches/admins** (architectural trade-off, ~30–60 min)

## 1. Search Debouncing (CRITICAL – Every Keystroke Fires a Request)

Right now, typing in search fields triggers a network request on **every character** when in server-side mode.

### Issues

| Location | File:Lines | Problem |
|---|---|---|
| Members tab search | `lib/screens/admin_home_screen.dart:968–979` | `_onSearchChanged` cancels `_searchDebounce` (declared at 793, never restarted) and calls `_fetchMembers(reset: true)` immediately. No debounce scheduled. |
| Exercises tab search (Settings) | `lib/screens/admin_settings_screen.dart:1908–1915` | `onChanged` calls `load(reset: true)` immediately on every keystroke with no Timer/debounce. |

### Impact
Very High – typing "john smith" (10 chars) = 10 separate network requests. Multiplies with typing speed.

### Recommended Fix

**admin_home_screen.dart**

```dart
Timer? _searchDebounce;

void _onSearchChanged(String v) {
  setState(() => searchQuery = v.trim());
  if (isClientSideMode) {
    setState(() {});
    return;
  }
  _searchDebounce?.cancel();
  _searchDebounce = Timer(const Duration(milliseconds: 300), () {
    _fetchMembers(reset: true);
  });
}
```

**admin_settings_screen.dart (Exercises tab)**

```dart
Timer? _exercisesSearchDebounce;

// In the TextField onChanged:
onChanged: (v) {
  search = v.trim();
  _exercisesSearchDebounce?.cancel();
  _exercisesSearchDebounce = Timer(const Duration(milliseconds: 300), () {
    load(reset: true);
  });
}
```

> Also ensure Timers are cancelled in `dispose()` (members already does this at line 804).

## 2. Unbounded List Reads (CRITICAL – Loading Entire Tables)

Several queries have **no `.limit()` or `.range()`**, pulling entire tables into memory every time a modal or tab loads. These are easy wins with low risk.

| Query | File:Lines | Current | Suggested | Rationale |
|---|---|---|---|---|
| **Diet members modal** (loads entire `diets` table, client-side filters/groups) | `lib/screens/admin_home_screen.dart:611–614` | `.order('updated_at', ascending: false)` – **no limit** | `.order('updated_at', ascending: false).limit(200)` | Does heavy client-side processing after full table read. Best long-term: move "latest diet per member + needs-update" logic to an RPC. |
| **Member status modals** (expiring/expired/inactive) | `lib/screens/admin_home_screen.dart:505–533` | Query built with filters, **no `.limit()`** | Add `.limit(500)` to the final query | Modals don't need thousands of rows. Caps worst-case egress. |
| **Pending payments** | `lib/screens/admin_home_screen.dart:1956–1963` | `.eq('status','pending').order('payment_date', ascending: true)` – **no limit** | `.eq('status','pending').order('payment_date', ascending: true).limit(200)` | Grows with queue size. If queue exceeds 200, add pagination instead. |
| **All `offer_members` (global maps)** | `lib/screens/admin_settings_screen.dart:404–406, 844–846` | Unbounded selects on `offer_members` | `.limit(500)` | These load on Offers tab open. Note: per-offer assigned members (line 746–748) are already scoped by `offer_id` and are fine. |

### Example Patch

```dart
final diets = await Supabase.instance.client
    .from('diets')
    .select('member_id, updated_at, profiles(full_name, email)')
    .order('updated_at', ascending: false)
    .limit(200);
```

## 3. Realtime Fan-Out for Coaches/Admins (HIGH – Broadcasts All Row Changes)

### Confirmed Behavior

In `master_data_provider.dart:_initRealtimeSubscription()` (lines **319–371**), all 5 global channels are created **without `PostgresChangeFilter`**:

- `public:profiles` – `PostgresChangeEvent.update` only, **no filter** (line 325)
- `public:payments` – `PostgresChangeEvent.all`, **no filter** (line 335)
- `public:diets` – `PostgresChangeEvent.all`, **no filter** (line 345)
- `public:workouts` – `PostgresChangeEvent.all`, **no filter** (line 355)
- `public:measurement_logs` – `PostgresChangeEvent.all`, **no filter** (line 365)

### Impact

Coach/admin devices receive **every INSERT/UPDATE/DELETE** event for **all rows** across those 5 tables, for **every member**. Client-side handlers filter by `member_id` (e.g. `_handleMemberTableChange` at 427–450) and early-return if irrelevant, but the **event payloads are still delivered over Realtime**. With multiple online coaches + frequent writes, fan-out grows linearly (N coaches × M row-changes).

### Trade-off Options

| Option | Egress | Complexity | Visibility | Recommendation |
|---|---|---|---|---|
| **A. Keep global (as-is)** | Highest at scale | Lowest | Full visibility for all staff | Acceptable if you have a small coaching team. |
| **B. Scope by assignment** | Much lower | Medium | Coaches see assigned members only; admins/head_coach see all | **Best balance** for most teams. |
| **C. Per-screen subscribe/unsubscribe** | Minimal when idle | Higher | Easy to miss updates, churn risk | Not recommended for reliability. |

**Pragmatic recommendation:** Split logic. Keep **global, unfiltered channels for admins/head_coach** (they genuinely need cross-member visibility). For **coaches**, scope Realtime to members where `assigned_coach_id == current_uid` (or via a view/RLS-aware filter). This preserves correctness while cutting traffic significantly.

> Note: The **member role already does this correctly** with per-UID filtered channels (`public:profiles:$uid`, etc.). The coach/admin global path is the only outlier.

## 4. Avoid Full Refetches After Single-Row Mutations (HIGH ROI)

You already do this well in **Payments** (verify/reject removes the single item locally). Extend the same pattern to avoid re-reading entire lists on trivial updates.

| Area | File:Locations | Current | Suggestion |
|---|---|---|---|
| **Members tab** (assign category/coach, toggle is_active, payment complete) | `admin_home_screen.dart:992–997, 999–1004, 1360–1368, 1013–1016` | Calls `_fetchMembers(reset: true)` after single-row updates | Update the affected member in `members` list in-place + `setState()` instead of full refetch. |
| **Coaches tab** (toggle active, create coach) | `admin_home_screen.dart:1724–1731, 1535–1563` | Triggers full `_loadCoaches()` reload | Patch the single coach entry locally on success. |
| **Offers tab** (assign/remove member, create/edit/delete offer) | `admin_settings_screen.dart` (mutations around 545–589, 786–830, 1118–1196) | Often calls full `_loadData()`/`onRefresh()` | Refresh only affected offer/member lists instead of everything when feasible. |

This eliminates many 1-write → 1-full-page-read patterns with minimal behavioral change.

## 5. Minor Optimizations (Nice-to-Have)

| Change | File | Benefit |
|---|---|---|
| **Parallelize Offers `_loadData()`** | `admin_settings_screen.dart:372–398` | `offersData`, `_loadMemberOfferMap()`, and `_loadMembersPaginated(reset: true)` are independent. Use `Future.wait()` to reduce total load latency. |
| **Specify columns explicitly (replace bare `.select()`)** | `admin_settings_screen.dart:1621` (exercises), `2051` (foods), `2503` (categories), `admin_home_screen.dart:2335` (payments history) | Smaller payloads, clearer intent, less coupled to schema changes. |
| **Debounce streak refresh on measurement bursts** | `master_data_provider.dart:440, 564–576` | Each measurement row change calls `_refreshStreak` RPC. If multiple measurement events arrive in a burst, consider coalescing with a short timer (last-write-wins) to avoid RPC spam. You already coalesce UI notifications via `_patchNotifyTimer` (1500ms). |

## Priority & Expected Impact

| Priority | Recommendation | Effort | Expected Egress Reduction |
|---|---|---|---|
| **P0** | Add search debouncing (Members + Exercises) | 5–10 min | **High** – eliminates request storms while typing |
| **P0** | Add `.limit()` to unbounded queries (4 locations) | 10–15 min | **High** – caps worst-case reads on modals/tabs |
| **P1** | In-place updates after single-row mutations | 1–2 hours | **Medium–High** – removes many redundant full refetches |
| **P1** | Scope Realtime for coaches (vs global) | 30–60 min | **High at scale** – biggest win if multiple coaches write/read frequently |
| **P2** | Parallelize loads + explicit columns + burst coalescing | 30–60 min total | **Low–Medium** – polish/latency improvements |

**Quickest ROI:** Do P0 items first. They'll likely produce the most noticeable drop in Supabase usage with virtually zero behavior change or risk.