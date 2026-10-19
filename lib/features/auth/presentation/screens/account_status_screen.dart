import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/auth_controller.dart';
import '../../application/auth_state.dart';
import '../widgets/auth_widgets.dart';

class AccountStatusScreen extends ConsumerStatefulWidget {
  const AccountStatusScreen({super.key});

  @override
  ConsumerState<AccountStatusScreen> createState() =>
      _AccountStatusScreenState();
}

class _AccountStatusScreenState extends ConsumerState<AccountStatusScreen> {
  bool _isChecking = false;

  Future<void> _refreshStatus() async {
    setState(() => _isChecking = true);
    await ref.read(authControllerProvider.notifier).checkAuthStatus();
    if (!mounted) return;
    setState(() => _isChecking = false);
    // A pending account is never given a session, so there is nothing to
    // re-check here — only signing in again asks the server for the current
    // status. Without this the button left an approved rider stuck on
    // "Under Review".
    if (ref.read(authControllerProvider) is AuthUnauthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Log in again to see your latest account status.'),
        ),
      );
      context.go('/phone-login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isRejected =
        authState is AuthPendingApproval && authState.isRejected;
    final isDeactivated =
        authState is AuthPendingApproval && authState.isDeactivated;
    final rejectionReason = authState is AuthPendingApproval
        ? authState.rejectionReason
        : null;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 28.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96.w,
                height: 96.w,
                decoration: BoxDecoration(
                  color: (isRejected || isDeactivated ? Colors.redAccent : AppTheme.primaryColor)
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDeactivated
                      ? Icons.block_rounded
                      : isRejected
                          ? Icons.cancel_rounded
                          : Icons.hourglass_top_rounded,
                  color: isRejected || isDeactivated ? Colors.redAccent : AppTheme.primaryColor,
                  size: 48.sp,
                ),
              ),
              SizedBox(height: 28.h),
              Text(
                isDeactivated
                    ? 'Account Deactivated'
                    : isRejected
                        ? 'Application Rejected'
                        : 'Application Under Review',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12.h),
              Text(
                isDeactivated
                    ? 'Your account has been deactivated. Please contact support.'
                    : isRejected
                    ? (rejectionReason?.isNotEmpty == true
                          ? rejectionReason!
                          : 'Your application was not approved. Please contact support for details.')
                    : 'Our team is reviewing your documents. This usually takes 24-48 hours. We will notify you once approved.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  height: 1.5,
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withValues(alpha: 0.75),
                ),
              ),
              SizedBox(height: 36.h),
              AuthPrimaryButton(
                label: 'Refresh Status',
                isLoading: _isChecking,
                onPressed: _refreshStatus,
              ),
              SizedBox(height: 14.h),
              TextButton(
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).logout(),
                child: Text(
                  'Log out',
                  style: TextStyle(fontSize: 14.sp, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
