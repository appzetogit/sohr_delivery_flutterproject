import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';

class ReviewService {
  static final InAppReview _inAppReview = InAppReview.instance;

  /// Prompts the user for an in-app rating/review if available on the device.
  static Future<void> requestReview() async {
    try {
      final isAvailable = await _inAppReview.isAvailable();
      if (isAvailable) {
        debugPrint("In-App Review: Requesting native review prompt.");
        await _inAppReview.requestReview();
      } else {
        debugPrint("In-App Review API is not available on this device.");
      }
    } catch (e) {
      debugPrint("Error triggering In-App Review: $e");
    }
  }

  /// Opens the store listing (App Store / Play Store) directly.
  static Future<void> openStoreListing({String? appStoreId}) async {
    try {
      await _inAppReview.openStoreListing(appStoreId: appStoreId);
    } catch (e) {
      debugPrint("Error opening store listing: $e");
    }
  }
}
