import 'package:flutter/foundation.dart';

/// Debug-only trace for anything that costs Google Maps Platform money.
///
/// Every billable surface (a map load, a Directions/Places/Geocoding request)
/// logs through here so a duplicate or runaway caller is visible in the console
/// instead of only on the invoice. Compiled out of release builds.
///
/// Never pass an API key, token or any credential as [detail].
void mapsDebug(String event, [String detail = '']) {
  if (!kDebugMode) return;
  debugPrint('[MAPS] $event${detail.isEmpty ? '' : ' — $detail'}');
}
