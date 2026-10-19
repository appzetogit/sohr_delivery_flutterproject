# In-App Review Feature

This document explains how the In-App Review feature is implemented in the app codebase.

## Dependency

The feature utilizes the `in_app_review` Flutter plugin. It is declared in `pubspec.yaml` as follows:

```yaml
dependencies:
  # In-App Review
  in_app_review: ^2.0.12
```

## Core Implementation

The logic for triggering the in-app review is located in the review page, which is shown after a booking/ride is completed.

**File Location:** 
[review_page.dart](file:///c:/Users/rishi/Downloads/Appzeto-master/Appzeto-master/newappzeto_user/lib/features/bookingpage/presentation/page/review/page/review_page.dart)

### Trigger Conditions

The in-app review prompt is shown to the user **only if they provide a rating of 4 or higher** for their ride. This ensures that only users who had a positive experience are prompted to leave a review on the App Store or Google Play Store.

### Code Snippet

Within the `_ReviewPageState`, there is a `BlocListener` listening to the `BookingBloc`. When the user successfully submits their rating (`BookingUserRatingsSuccessState`), the code evaluates the rating and requests the review if the condition is met.

```dart
// Import required
import 'package:in_app_review/in_app_review.dart';

// ... Inside the BlocListener ...
listener: (context, state) async {
  if (state is BookingUserRatingsSuccessState) {
    // 1. Get the rating given by the user
    final rating = context.read<BookingBloc>().selectedRatingsIndex;
    
    // 2. Check if the rating is 4 or 5 stars
    if (rating >= 4) {
      try {
        final InAppReview inAppReview = InAppReview.instance;
        
        // 3. Check if the in-app review API is available on the device
        inAppReview.isAvailable().then((available) {
          if (available) {
            // 4. Request the review dialog to be shown
            inAppReview.requestReview();
          }
        });
      } catch (e) {
        debugPrint("Error triggering In-App Review: $e");
      }
    }
    
    // Continue navigation to the Home Page
    Navigator.pushNamedAndRemoveUntil(
        context, HomePage.routeName, (route) => false);
  }
  // ... other states ...
}
```

## Summary of Execution Flow
1. User completes a ride and is presented with the `ReviewPage`.
2. User selects a star rating (1 to 5) and optionally leaves feedback.
3. User taps the "Submit" button, which triggers the `BookingUserRatingsEvent`.
4. The `BookingBloc` processes this and emits `BookingUserRatingsSuccessState`.
5. The `BlocListener` catches this success state.
6. If the chosen rating is `>= 4`, the app uses `inAppReview.requestReview()` to prompt the native store review dialog.
7. Finally, the app navigates the user back to the `HomePage`.
