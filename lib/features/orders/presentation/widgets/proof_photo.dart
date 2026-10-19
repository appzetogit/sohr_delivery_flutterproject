import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/error/result.dart';
import '../../data/orders_repository.dart';

/// Where on the server a proof photo is filed.
enum ProofPhotoKind {
  /// The packed food / bill, taken at the counter before "Confirm pickup".
  pickup('sohr/delivery/pickup', 'Photo of the packed order',
      'Take a clear photo of the packed food and bill before you leave the counter.'),

  /// The order at the customer's door, taken before "Complete delivery".
  delivery('sohr/delivery/handover', 'Photo at handover',
      'Take a photo of the order being handed over at the customer\'s door.');

  const ProofPhotoKind(this.folder, this.title, this.hint);
  final String folder;
  final String title;
  final String hint;
}

/// Asks the rider for a proof photo, uploads it and returns its URL.
///
/// Returns null when the rider backs out or the upload fails (a snackbar says
/// why), so callers simply stop and the rider can tap the button again.
Future<String?> captureProofPhoto(
  BuildContext context,
  WidgetRef ref,
  ProofPhotoKind kind,
) async {
  final go = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(kind.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(kind.hint, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Open camera'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (go != true || !context.mounted) return null;

  final XFile? shot;
  try {
    // Small JPEG: enough to read a bill, cheap on mobile data.
    shot = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 60,
      maxWidth: 1280,
      maxHeight: 1280,
    );
  } catch (_) {
    if (context.mounted) _snack(context, 'Could not open the camera. Check camera permission.');
    return null;
  }
  if (shot == null || !context.mounted) return null;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  final result = await ref
      .read(ordersRepositoryProvider)
      .uploadProofPhoto(shot.path, folder: kind.folder);
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

  return result.when(
    success: (url) => url,
    failure: (error) {
      if (context.mounted) _snack(context, 'Photo upload failed: ${error.message}');
      return null;
    },
  );
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
