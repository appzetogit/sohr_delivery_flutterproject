# 📱 Flutter In-App Update Implementation Guide

This step-by-step developer manual guides you through implementing or reproducing the Google Play In-App Update feature in a Flutter application. 

The implementation uses the `in_app_update` plugin to auto-detect new store versions, prompt users, and trigger **Flexible** (background update with optional install prompt) or **Immediate** (forced fullscreen update) updates.

---

## 🛠️ Step 1: Add Dependency to `pubspec.yaml`

Add the `in_app_update` package under `dependencies` in your [pubspec.yaml](file:///c:/Users/rishi/Downloads/bakala_user/bakala_user/pubspec.yaml) file:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # ... other dependencies ...
  
  # Google Play In-App Update Plugin
  in_app_update: ^4.2.0
```

### 📥 Run Dependency Command
After adding the dependency, fetch the packages by running:
```bash
flutter pub get
```

---

## 📂 Step 2: Create the Update Service

Create a new service file at [lib/services/update_service.dart](file:///c:/Users/rishi/Downloads/bakala_user/bakala_user/lib/services/update_service.dart) to manage checking, downloading, and applying updates.

> [!IMPORTANT]
> Since Google Play In-App Updates are only supported on Android, this service includes a guard clause (`Platform.isAndroid`) to prevent crashes on iOS, web, or desktop platforms.

```dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

class UpdateService {
  /// Checks for available updates on the Google Play Store (Android only).
  ///
  /// For flexible updates, it starts the download and completes it automatically.
  /// For immediate updates, it displays a fullscreen overlay blocking app usage.
  static Future<void> checkForUpdate() async {
    // In-app updates are only supported on Android.
    if (!Platform.isAndroid) {
      debugPrint("In-App Update: Supported on Android only. Skipping check.");
      return;
    }

    try {
      debugPrint("In-App Update: Checking for available updates...");
      final AppUpdateInfo updateInfo = await InAppUpdate.checkForUpdate();

      if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
        debugPrint("In-App Update: An update is available.");

        // 1. Check if an immediate update is allowed/required by Google Play
        if (updateInfo.immediateUpdateAllowed) {
          debugPrint("In-App Update: Starting immediate (forced) update flow.");
          final AppUpdateResult result = await InAppUpdate.performImmediateUpdate();
          debugPrint("In-App Update: Immediate update completed with result: $result");
        } 
        // 2. Otherwise, check if a flexible update is allowed
        else if (updateInfo.flexibleUpdateAllowed) {
          debugPrint("In-App Update: Starting flexible (background) update flow.");
          final AppUpdateResult result = await InAppUpdate.startFlexibleUpdate();
          
          if (result == AppUpdateResult.success) {
            debugPrint("In-App Update: Flexible update download successful. Completing update...");
            await InAppUpdate.completeFlexibleUpdate();
            debugPrint("In-App Update: Flexible update applied successfully.");
          } else {
            debugPrint("In-App Update: Flexible update cancelled or failed with result: $result");
          }
        } else {
          debugPrint("In-App Update: Update available, but neither immediate nor flexible updates are allowed.");
        }
      } else {
        debugPrint("In-App Update: App is up to date.");
      }
    } catch (e) {
      debugPrint("In-App Update Error: Update check failed: $e");
    }
  }
}
```

---

## ⚡ Step 3: Trigger Update Checks in `SplashScreen`

To verify updates as soon as the app starts, call `UpdateService.checkForUpdate()` inside the `initState` of your app's initial widget. In this project, that is [lib/screens/splash_screen.dart](file:///c:/Users/rishi/Downloads/bakala_user/bakala_user/lib/screens/splash_screen.dart).

### 🔍 Diffs of changes made to `splash_screen.dart`

```diff
  import 'package:webview_master_app/utils/permission_handler_util.dart';
  import 'package:webview_master_app/utils/notification_service.dart';
+ import 'package:webview_master_app/services/update_service.dart';
  
  import 'package:webview_master_app/screens/webview_screen.dart';
```

```diff
    @override
    void initState() {
      super.initState();
      _setupAnimations();
+     UpdateService.checkForUpdate();
      _navigateAfterDelay();
    }
```

---

## 🤖 Step 4: Verify Android Configurations

To ensure the native Android side handles the updates correctly, verify the following configuration points:

### 1. Minimum SDK Version Support
The Google Play In-App Updates API requires a minimum Android SDK version of **21** (Android 5.0).
Inside [android/app/build.gradle](file:///c:/Users/rishi/Downloads/bakala_user/bakala_user/android/app/build.gradle), verify the `minSdkVersion` setting. 
* By default, this app uses `flutter.minSdkVersion` which is dynamically configured by your Flutter SDK.
* If you ever encounter compilation issues or need to force it, change:
  ```gradle
  defaultConfig {
      minSdkVersion 21 // Force minSdkVersion to 21
  }
  ```

### 2. Internet Permissions
Ensure that your app includes the `<uses-permission android:name="android.permission.INTERNET" />` inside the manifest file `android/app/src/main/AndroidManifest.xml`. (This is standard on almost all Flutter applications).

---

## 🧪 Step 5: Testing the Update Flow

Testing in-app updates requires careful steps because the API connects directly to the Google Play Store backend.

> [!WARNING]
> **Do not test this using a standard local debug build!**
> If you run a debug build (`flutter run`), the app check will fail with an error or return `updateAvailability = 0` (no update available) or `Install Error(-10)` because the local app does not have Google Play ownership signature.

### 📋 Correct Testing Procedure:
1. **Upload an initial build:** Make a release build with a low `versionCode` (e.g., `versionCode: 100` / `versionName: 5.5.6`) and upload it to the **Internal Testing Track** of your Google Play Console.
2. **Install from Google Play:** Join the internal testing group on your device, open the opt-in link, and install the app directly from the Google Play Store. This establishes Google Play ownership signature.
3. **Upload an update build:** Bump your version code and name in `pubspec.yaml` (e.g., `version: 5.5.7+101`), compile the app bundle, and upload it to the **Internal Testing Track**.
4. **Trigger Check:** Do not open the Play Store page. Simply relaunch the app on your testing device. The `UpdateService` will detect the updated version on Google Play and prompt you with either the **Flexible** or **Immediate** update interface!

---

## 💡 Troubleshooting Common Errors

| Error / Behavior | Likely Cause | Solution |
| :--- | :--- | :--- |
| **`Install Error(-10)`** | App not installed from Play Store. | Install the app via the Play Store's **Internal Testing Track** first. |
| **`updateAvailability == 0`** | Version numbers are not different, or cache isn't cleared. | Clear Google Play Store app data on your device, increase `versionCode` in `pubspec.yaml`, and re-upload the app bundle. |
| **Silent Failures in Logs** | Trying to test on iOS, Simulator, or Emulator without Play Services. | Run the check exclusively on physical Android devices with working Google Play Services. |

---

> [!TIP]
> * **Flexible Updates** let the user continue using the app while downloading in the background. Good for general improvements.
> * **Immediate Updates** are a fullscreen blocking UI. Excellent for critical patches, hotfixes, or breaking API changes.
