import 'dart:io';

import 'package:sohr_delivery_partner/features/language/domain/models/language_listing_model.dart';

class AppConstants {
  static const String title = 'Sohr Delivery Partner';

  /// Consumer-facing brand, used in share text and the referral ticket.
  static const String brandName = 'Sohr Delivery Partner';
  static const String brandSuffix = 'Delivery';
  static const String appFontFamily = 'Latin';

  /// One backend for both verticals.
  ///
  /// The rider fleet is shared: `/delivery/*` is mounted cross-vertical on the
  /// server, so a single host serves food and quick jobs alike and this app
  /// never picks a vertical. Overridable at build time so a staging build needs
  /// no code edit:
  ///   flutter build apk --dart-define=API_HOST=https://staging.example.com
  static const String apiHost = String.fromEnvironment(
    'API_HOST',
    defaultValue: 'https://sohr.in',
  );
  static const String baseUrl = '$apiHost/api/v1';

  static String resolveMediaUrl(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return '';
    if (v.startsWith('http://') ||
        v.startsWith('https://') ||
        v.startsWith('data:')) {
      return v;
    }
    final path = v.startsWith('/') ? v : '/$v';
    return '$apiHost$path';
  }

  static String firbaseApiKey = (Platform.isAndroid)
      ? "AIzaSyAtdqDxYi7GRwHC-P9rkh7GU_CMDeR4h9k"
      : "ios firebase api key";

  static String firebaseAppId = (Platform.isAndroid)
      ? "1:347537941281:android:7de746f210e8ddc88d9460"
      : "ios firebase app id";

  static String firebasemessagingSenderId = (Platform.isAndroid)
      ? "347537941281"
      : "ios firebase sender id";

  static String firebaseProjectId = (Platform.isAndroid)
      ? "sohr-efd83"
      : "ios firebase project id";

  static const String mapKey = String.fromEnvironment(
    'MAPS_API_KEY',
    defaultValue: 'AIzaSyBbtwNQfVuTpYXe5IUv-g6ZJZMcjgbDul0',
  );

  static const String stripPublishKey = '';

  static List<LocaleLanguageList> languageList = [
    LocaleLanguageList(name: 'English', lang: 'en'),
  ];

  static String packageName = 'com.appzetofood.delivery';
  static String signKey = '';
}
