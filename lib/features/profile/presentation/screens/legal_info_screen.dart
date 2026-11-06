import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/constants/legal_info.dart';

/// Who runs the app, how to reach them, and the policies that apply.
class LegalInfoScreen extends StatelessWidget {
  const LegalInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subTextColor = theme.textTheme.bodySmall?.color ?? Colors.grey;

    return Scaffold(
      appBar: AppBar(title: const Text('About & policies')),
      body: ListView(
        padding: EdgeInsets.all(16.r),
        children: [
          Container(
            padding: EdgeInsets.all(16.r),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This app is owned and operated by',
                  style: TextStyle(fontSize: 12.sp, color: subTextColor),
                ),
                SizedBox(height: 6.h),
                SelectableText(
                  LegalInfo.legalName,
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Trading as ${LegalInfo.brand}',
                  style: TextStyle(fontSize: 12.sp, color: subTextColor),
                ),
                SizedBox(height: 12.h),
                SelectableText(LegalInfo.address, style: TextStyle(fontSize: 13.sp)),
                SizedBox(height: 8.h),
                InkWell(
                  onTap: () => LegalInfo.open(LegalInfo.phoneUri),
                  child: Text(
                    LegalInfo.phone,
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: theme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16.h),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Column(
              children: [
                for (final (title, path) in LegalInfo.pages)
                  ListTile(
                    title: Text(title),
                    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: () => LegalInfo.open(path),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
