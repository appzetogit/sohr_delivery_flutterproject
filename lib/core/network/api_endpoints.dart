/// Central catalog of backend API paths (relative to [AppConstants.baseUrl]).
class ApiEndpoints {
  ApiEndpoints._();

  // Auth
  static const String requestOtp = '/food/auth/delivery/request-otp';
  static const String verifyOtp = '/food/auth/delivery/verify-otp';
  static const String refreshToken = '/food/auth/refresh-token';
  static const String logout = '/food/auth/logout';
  static const String me = '/food/auth/me';

  // Registration & profile
  static const String register = '/food/delivery/register';
  static String checkVehicle(String number) =>
      '/food/delivery/check-vehicle/$number';
  static const String profile = '/food/delivery/profile';
  static const String profileDetails = '/food/delivery/profile/details';
  static const String profilePhotoBase64 =
      '/food/delivery/profile/photo-base64';
  static const String profileBankDetails =
      '/food/delivery/profile/bank-details';
  static const String deleteAccount = '/food/delivery/profile/account';
  static const String reverify = '/food/delivery/reverify';

  // Availability
  static const String availability = '/food/delivery/availability';

  // Orders
  static const String ordersAvailable = '/food/delivery/orders/available';
  static const String ordersCurrent = '/food/delivery/orders/current';
  static String orderDetails(String orderId) =>
      '/food/delivery/orders/$orderId';
  static String orderAccept(String orderId) =>
      '/food/delivery/orders/$orderId/accept';
  static String orderReject(String orderId) =>
      '/food/delivery/orders/$orderId/reject';
  static String orderReachedPickup(String orderId) =>
      '/food/delivery/orders/$orderId/reached-pickup';
  static String orderConfirmPickup(String orderId) =>
      '/food/delivery/orders/$orderId/confirm-pickup';
  static String orderReachedDrop(String orderId) =>
      '/food/delivery/orders/$orderId/reached-drop';
  static String orderComplete(String orderId) =>
      '/food/delivery/orders/$orderId/complete';
  static String orderStatus(String orderId) =>
      '/food/delivery/orders/$orderId/status';
  static String orderRoute(String orderId) =>
      '/food/delivery/orders/$orderId/route';
  static String orderRateCustomer(String orderId) =>
      '/food/delivery/orders/$orderId/rate-customer';

  // Payment collection
  static String collectQr(String orderId) =>
      '/food/delivery/orders/$orderId/collect/qr';
  static String paymentStatus(String orderId) =>
      '/food/delivery/orders/$orderId/payment-status';
  static String collectCash(String orderId) =>
      '/food/delivery/orders/$orderId/collect/cash';

  // Wallet
  static const String wallet = '/food/delivery/wallet';
  static const String walletWithdraw = '/food/delivery/wallet/withdraw';

  /// Generic image upload (multipart field `file`, `?folder=`); returns `data.url`.
  static const String uploadImage = '/uploads/image';
  static const String walletDepositOrder =
      '/food/delivery/wallet/deposit/order';
  static const String walletDepositVerify =
      '/food/delivery/wallet/deposit/verify';

  // Earnings / trips / settings
  static const String earnings = '/food/delivery/earnings';
  static const String tripHistory = '/food/delivery/trip-history';
  static const String pocketDetails = '/food/delivery/pocket-details';
  static const String earningAddonsActive =
      '/food/delivery/earning-addons/active';
  static const String cashLimit = '/food/delivery/cash-limit';
  static const String emergencyHelp = '/food/delivery/emergency-help';
  static const String referralStats = '/food/delivery/referrals/stats';

  // Support tickets
  static const String supportTickets = '/food/delivery/support-tickets';
  static String supportTicketDetails(String id) =>
      '/food/delivery/support-tickets/$id';

  // Emergency order reassignment
  static const String emergencyRequests =
      '/food/delivery/order-emergency-requests';
  static String emergencyRequestDetails(String id) =>
      '/food/delivery/order-emergency-requests/$id';

  // Chat
  static const String chatMessages = '/food/chat/messages';
  static const String chatConversations = '/food/chat/conversations';
  static String chatConversationRead(String conversationId) =>
      '/food/chat/conversations/$conversationId/read';

  // Push notifications
  static const String fcmTokenSaveMobile = '/fcm-tokens/mobile/save';
  static const String fcmTokenRemove = '/fcm-tokens/remove';
  static const String notificationsInbox = '/food/notifications/inbox';
  static String notificationRead(String id) =>
      '/food/notifications/$id/read';
  static String notificationDelete(String id) => '/food/notifications/$id';
  static const String notificationsDeleteAll =
      '/food/notifications/inbox/all';
}
