import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../storage/token_storage.dart';
import 'auth_event_bus.dart';
import 'auth_interceptor.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  dio.interceptors.add(
    AuthInterceptor(
      tokenStorage: ref.read(tokenStorageProvider),
      authEventBus: ref.read(authEventBusProvider),
    ),
  );

  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(
        request: false,
        requestHeader: false,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        error: true,
      ),
    );
  }

  return dio;
});
