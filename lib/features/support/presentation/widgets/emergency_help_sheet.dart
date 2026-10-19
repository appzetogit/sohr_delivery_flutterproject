import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:sohr_delivery_partner/core/error/result.dart';
import 'package:sohr_delivery_partner/core/theme/app_colors.dart';
import 'package:sohr_delivery_partner/features/support/data/support_repository.dart';
import 'package:url_launcher/url_launcher.dart';

/// Emergency helplines, fetched from `/food/delivery/emergency-help`.
///
/// Single implementation shared by the dashboard header and the Help Centre —
/// the numbers are admin-configured, so nothing here is hardcoded.
Future<void> showEmergencyHelpSheet(BuildContext context, WidgetRef ref) async {
  final result = await ref.read(supportRepositoryProvider).getEmergencyHelp();
  if (!context.mounted) return;

  final data = result.when(
    success: (d) => d,
    failure: (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return null;
    },
  );
  if (data == null || !context.mounted) return;

  final c = AppColors.of(context);

  await showModalBottomSheet(
    context: context,
    backgroundColor: c.background,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: EdgeInsets.all(20.w),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Emergency Help',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w900,
                      color: c.textPrimary,
                    ),
                  ),
                  Icon(
                    Icons.report_problem_outlined,
                    color: AppColors.error,
                    size: 20.sp,
                  ),
                ],
              ),
              SizedBox(height: 20.h),
              for (final option in _options)
                _EmergencyTile(
                  option: option,
                  phone: data[option.key] as String?,
                ),
              SizedBox(height: 8.h),
            ],
          ),
        ),
      ),
    ),
  );
}

class _EmergencyOption {
  const _EmergencyOption(
    this.key,
    this.icon,
    this.color,
    this.title,
    this.subtitle,
  );

  final String key;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
}

const _options = [
  _EmergencyOption(
    'medicalEmergency',
    Icons.local_hospital_outlined,
    AppColors.error,
    'Medical Emergency',
    'Call an ambulance',
  ),
  _EmergencyOption(
    'accidentHelpline',
    Icons.warning_amber_rounded,
    AppColors.warning,
    'Accident Helpline',
    'Report an accident',
  ),
  _EmergencyOption(
    'contactPolice',
    Icons.shield_outlined,
    AppColors.primaryDark,
    'Contact Police',
    'Nearest police support',
  ),
  _EmergencyOption(
    'insurance',
    Icons.verified_user_outlined,
    AppColors.success,
    'Insurance',
    'Policy & claim help',
  ),
];

class _EmergencyTile extends StatelessWidget {
  const _EmergencyTile({required this.option, required this.phone});

  final _EmergencyOption option;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasPhone = phone != null && phone!.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        // Admin hasn't configured this line — leave it visibly inert rather
        // than dialling nothing.
        onTap: hasPhone ? () => _dial(phone!) : null,
        child: Container(
          padding: EdgeInsets.all(16.r),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.r),
                decoration: BoxDecoration(
                  color: option.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(option.icon, color: option.color, size: 20.sp),
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      hasPhone ? phone! : 'Not available',
                      style: TextStyle(fontSize: 12.sp, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              if (hasPhone)
                Icon(Icons.call_outlined, color: c.textSecondary, size: 18.sp),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _dial(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}
