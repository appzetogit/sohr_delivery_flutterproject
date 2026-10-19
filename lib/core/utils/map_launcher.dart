import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

class MapLauncher {
  /// Opens the Google Maps link the customer shared; with no link, searches the
  /// typed address. Returns false when nothing could be opened.
  static Future<bool> openCustomerLocation({
    required String link,
    required String address,
  }) async {
    final uri = link.isNotEmpty
        ? Uri.tryParse(link)
        : address.isNotEmpty
            ? Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': address})
            : null;
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> launchGoogleMaps(double lat, double lng) async {
    final String url;
    if (Platform.isAndroid) {
      url = 'google.navigation:q=$lat,$lng&mode=d';
    } else if (Platform.isIOS) {
      url = 'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving';
    } else {
      url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    }

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Fallback to web if native app can't be launched
      final webUri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri);
      }
    }
  }
}
