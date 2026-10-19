import 'dart:convert';

String? _extractUserId(dynamic value) {
  if (value is Map) return (value['_id'] ?? value['id'])?.toString();
  if (value is String && value.isNotEmpty) return value;
  return null;
}

/// An add-on chosen for a product line, priced as at order time.
class OrderItemAddon {
  const OrderItemAddon({required this.name, required this.price});

  final String name;
  final double price;

  factory OrderItemAddon.fromJson(Map<String, dynamic> json) {
    return OrderItemAddon(
      name: json['name'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// One product line on a Quick Commerce order.
///
/// Mirrors the backend's `orderItemSchema`. The catalogue fields — [brand],
/// [packSize], [image], [compareAtPrice] — are snapshotted at order time, so
/// they stay truthful even after the seller edits the product.
class OrderItem {
  const OrderItem({
    required this.name,
    required this.price,
    required this.quantity,
    this.itemId,
    this.image,
    this.brand,
    this.packSize,
    this.categoryName,
    this.variantName,
    this.compareAtPrice = 0,
    this.gstRate,
    this.addons = const [],
    this.isVeg = true,
    this.notes,
  });

  final String name;

  /// Unit price actually charged, add-ons already folded in.
  final double price;
  final int quantity;
  final String? itemId;
  final String? image;

  /// e.g. "Amul" — shown under the product name when present.
  final String? brand;

  /// Free text from the seller: "500 g", "pack of 6".
  final String? packSize;
  final String? categoryName;
  final String? variantName;

  /// Compare-at / printed price snapshot (`otherPrice`). Shown struck through
  /// only when it genuinely exceeds [price].
  final double compareAtPrice;

  /// Per-line GST percentage. `null` means the order-wide rate applied.
  final double? gstRate;
  final List<OrderItemAddon> addons;
  final bool isVeg;
  final String? notes;

  /// What this line costs in total — the number that should be summed.
  double get lineTotal => price * quantity;

  bool get hasDiscount => compareAtPrice > price && price > 0;

  /// "500 g · Amul" — the secondary line under the product name, built from
  /// whatever the seller actually filled in.
  String get subtitle => [
    packSize,
    brand,
    variantName,
  ].where((e) => e != null && e.isNotEmpty).join(' · ');

  static String? _trimmedOrNull(dynamic value) {
    final v = (value as String?)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      name: json['name'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      itemId: _trimmedOrNull(json['itemId']),
      image: _trimmedOrNull(json['image']),
      brand: _trimmedOrNull(json['brand']),
      packSize: _trimmedOrNull(json['packSize']),
      categoryName: _trimmedOrNull(json['categoryName']),
      variantName: _trimmedOrNull(json['variantName']),
      compareAtPrice: (json['otherPrice'] as num?)?.toDouble() ?? 0,
      gstRate: (json['gstRate'] as num?)?.toDouble(),
      addons: (json['addons'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(OrderItemAddon.fromJson)
          .toList(),
      isVeg: json['isVeg'] as bool? ?? true,
      notes: _trimmedOrNull(json['notes']),
    );
  }
}

class GeoPoint {
  const GeoPoint({required this.lat, required this.lng});
  final double lat;
  final double lng;

  static GeoPoint? fromCoordinates(dynamic coordinates) {
    if (coordinates is! List || coordinates.length < 2) return null;
    final lng = (coordinates[0] as num?)?.toDouble();
    final lat = (coordinates[1] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return GeoPoint(lat: lat, lng: lng);
  }
}

class RestaurantInfo {
  const RestaurantInfo({
    required this.name,
    this.phone,
    this.addressLine1,
    this.area,
    this.city,
    this.profileImage,
    this.coverImage,
    this.coverImages = const [],
    this.galleryImages = const [],
    this.menuImages = const [],
    this.location,
    this.landmark,
  });

  final String name;
  final String? phone;
  final String? addressLine1;
  final String? area;
  final String? city;
  final String? profileImage;

  /// Single hero image for the restaurant page.
  final String? coverImage;
  final List<String> coverImages;

  /// Photos of the PREMISES, uploaded specifically so the rider can recognise
  /// the storefront at pickup — the admin panel labels this
  /// "Premises Gallery — shown to the delivery partner at pickup".
  ///
  /// The backend has always sent it; this model simply never read it, so the
  /// one field meant for this screen was the one the rider never saw.
  final List<String> galleryImages;

  /// Seller-uploaded catalogue/shelf photos (wire key `menuImages`).
  final List<String> menuImages;
  final GeoPoint? location;

  /// Free-text landmark the seller gave, e.g. "Near SBI ATM".
  final String? landmark;

  String get address =>
      [addressLine1, area, city].where((e) => e != null && e.isNotEmpty).join(', ');

  /// All store-uploaded photos (premises + catalogue media first, profile logo
  /// last as a fallback), deduped and with empty/null entries removed, for
  /// use in a gallery viewer.
  List<String> get allImages {
    final seen = <String>{};
    final result = <String>[];
    for (final url in [
      // Premises photos first: they are the ones taken for this exact purpose.
      ...galleryImages,
      ?coverImage,
      ...coverImages,
      ...menuImages,
      ?profileImage,
    ]) {
      if (url.isNotEmpty && seen.add(url)) result.add(url);
    }
    return result;
  }

  /// The photo shown on the map marker and pickup card — prefers the
  /// store's uploaded "Media" (cover/gallery) photos over the plain
  /// profile logo, since that's what the delivery partner should recognize
  /// the storefront by.
  String? get displayImage {
    // Same order as allImages: a premises photo beats a marketing cover, which
    // beats a catalogue shot, which beats the logo.
    if (galleryImages.isNotEmpty) return galleryImages.first;
    if (coverImage != null && coverImage!.isNotEmpty) return coverImage;
    if (coverImages.isNotEmpty) return coverImages.first;
    if (menuImages.isNotEmpty) return menuImages.first;
    return profileImage;
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<String>().where((e) => e.isNotEmpty).toList();
  }

  factory RestaurantInfo.fromJson(Map<String, dynamic> json) {
    return RestaurantInfo(
      name: json['restaurantName'] as String? ?? json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? json['ownerPhone'] as String?,
      addressLine1: json['addressLine1'] as String? ?? json['address'] as String?,
      area: json['area'] as String?,
      city: json['city'] as String?,
      profileImage: json['profileImage'] as String?,
      coverImage: json['coverImage'] as String?,
      coverImages: _stringList(json['coverImages']),
      galleryImages: _stringList(json['galleryImages']),
      menuImages: _stringList(json['menuImages']),
      location: GeoPoint.fromCoordinates(
        (json['location'] as Map<String, dynamic>?)?['coordinates'],
      ),
      landmark: (json['landmark'] as String?)?.trim(),
    );
  }
}

String _mapsLink(dynamic v) {
  final link = (v ?? '').toString().trim();
  return link.startsWith('http://') || link.startsWith('https://') ? link : '';
}

class DeliveryAddress {
  const DeliveryAddress({
    required this.street,
    this.additionalDetails,
    this.city,
    this.state,
    this.phone,
    this.location,
    this.label,
  });

  final String street;
  final String? additionalDetails;
  final String? city;
  final String? state;
  final String? phone;
  final GeoPoint? location;

  /// "Home" | "Office" | "Other" — shown as a chip on the drop card.
  final String? label;

  String get fullAddress => [
    street,
    additionalDetails,
    city,
  ].where((e) => e != null && e.isNotEmpty).join(', ');

  factory DeliveryAddress.fromJson(Map<String, dynamic> json) {
    return DeliveryAddress(
      street: json['street'] as String? ?? json['address'] as String? ?? '',
      additionalDetails: json['additionalDetails'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      phone: json['phone'] as String?,
      location: GeoPoint.fromCoordinates(
        (json['location'] as Map<String, dynamic>?)?['coordinates'],
      ),
      label: (json['label'] as String?)?.trim(),
    );
  }
}

class DeliveryOrder {
  const DeliveryOrder({
    required this.id,
    required this.orderCode,
    required this.orderStatus,
    required this.currentPhase,
    required this.restaurant,
    required this.deliveryAddress,
    required this.items,
    required this.customerName,
    required this.customerPhone,
    this.customerId,
    this.customerPhoto,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.total,
    required this.riderEarning,
    this.deliveryTip = 0,
    required this.dropOtpRequired,
    required this.dropOtpVerified,
    this.deliveryInstructions,
    this.cookingNote,
    this.pickupDistanceKm,
    this.tripDistanceKm,
    this.tripDurationMins,
    this.acceptanceDeadlineAt,
    this.vertical,
    this.assignedByAdmin = false,
    this.customerLocationLink = '',
    this.displayNumber = '',
    this.pickupPin = '',
  });

  final String id;
  final String orderCode;
  final String orderStatus;
  final String currentPhase;
  final RestaurantInfo restaurant;
  final DeliveryAddress deliveryAddress;
  final List<OrderItem> items;
  final String customerName;
  final String customerPhone;
  final String? customerId;
  final String? customerPhoto;
  final String paymentMethod;
  final String paymentStatus;
  final double total;
  final double riderEarning;

  /// The customer's tip, which is the rider's in full and is already included
  /// in [riderEarning]. Kept separate so it can be shown as its own line rather
  /// than disappearing into the total.
  final double deliveryTip;

  /// Distance/base pay, i.e. the earning before the tip.
  double get baseEarning =>
      (riderEarning - deliveryTip).clamp(0, double.infinity);
  final bool dropOtpRequired;
  final bool dropOtpVerified;
  final String? deliveryInstructions;
  final String? cookingNote;
  final double? pickupDistanceKm;
  final double? tripDistanceKm;
  final double? tripDurationMins;
  final DateTime? acceptanceDeadlineAt;

  /// Which vertical the order belongs to: 'food' | 'quick'. Null on payloads
  /// from a backend that predates the field.
  final String? vertical;

  /// An admin pushed this order onto the rider, possibly mid-trip. These are
  /// the only offers shown (and accepted) while a delivery is running.
  final bool assignedByAdmin;

  /// Google Maps link the customer shared (WhatsApp orders); '' when none.
  final String customerLocationLink;

  /// Short per-day number the kitchen calls out ("006"); '' on older orders.
  final String displayNumber;

  /// 4-digit code the rider shows at the counter so staff hand the food to
  /// the right rider. Only sent once this rider has accepted; '' otherwise.
  final String pickupPin;

  /// "#006" when the daily number exists, else the long order code.
  String get shortLabel =>
      displayNumber.isNotEmpty ? '#$displayNumber' : orderCode;

  bool get isMartOrder => vertical == 'quick';

  /// Rider-facing order-type label, null when the wire didn't say.
  String? get serviceLabel => switch (vertical) {
        'quick' => 'Mart',
        'food' => 'Food',
        _ => null,
      };

  /// Customer-facing brand the pickup belongs to, null when the wire didn't
  /// say (payloads from a backend that predates the vertical field).
  String? get brandName => switch (vertical) {
        'quick' => 'HiberMart',
        'food' => 'Sohr Food',
        _ => null,
      };

  bool get isCashOnDelivery => paymentMethod == 'cash';
  bool get isPaid => paymentStatus == 'paid';

  /// Distinct products on the order.
  int get productCount => items.length;

  /// Total units to hand over. This is the number that must match what comes
  /// off the shelf — three of one product is three things to carry, not one.
  int get totalUnits => items.fold(0, (sum, item) => sum + item.quantity);

  /// "3 products · 7 items", collapsing to a single clause when they agree.
  String get itemsSummary {
    final products = '$productCount ${productCount == 1 ? 'product' : 'products'}';
    if (totalUnits == productCount) return products;
    return '$products · $totalUnits items';
  }

  /// Phase-ordered progress, 0-based, for the trip stepper.
  static const List<String> phaseOrder = [
    'en_route_to_pickup',
    'at_pickup',
    'en_route_to_delivery',
    'at_drop',
    'delivered',
    'completed',
  ];

  int get phaseIndex {
    final i = phaseOrder.indexOf(currentPhase);
    return i < 0 ? 0 : i;
  }

  /// True while the rider is still heading to / standing at the store.
  bool get isPickupPhase =>
      currentPhase == 'en_route_to_pickup' || currentPhase == 'at_pickup';

  /// The `target` query value [ApiEndpoints.orderRoute] expects for the
  /// current phase. The wire value is still `restaurant` — the backend field
  /// names are unchanged by the quick-commerce move.
  String get routeTarget => isPickupPhase ? 'restaurant' : 'customer';

  /// Where the rider is headed right now.
  GeoPoint? get activeDestination =>
      isPickupPhase ? restaurant.location : deliveryAddress.location;

  /// Quick-commerce vocabulary for the same pickup point.
  ///
  /// The two rider apps named this differently — `restaurant` on the food side,
  /// `store` on the grocery side — while reading the identical wire field. The
  /// merged app keeps one implementation and answers to both names, so screens
  /// carried over from either side compile untouched.
  RestaurantInfo get store => restaurant;

  String? get storeNote => cookingNote;

  DeliveryOrder copyWith({bool? dropOtpRequired, bool? dropOtpVerified}) {
    return DeliveryOrder(
      id: id,
      orderCode: orderCode,
      orderStatus: orderStatus,
      currentPhase: currentPhase,
      restaurant: restaurant,
      deliveryAddress: deliveryAddress,
      items: items,
      customerName: customerName,
      customerPhone: customerPhone,
      customerId: customerId,
      customerPhoto: customerPhoto,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      total: total,
      riderEarning: riderEarning,
      deliveryTip: deliveryTip,
      dropOtpRequired: dropOtpRequired ?? this.dropOtpRequired,
      dropOtpVerified: dropOtpVerified ?? this.dropOtpVerified,
      deliveryInstructions: deliveryInstructions,
      cookingNote: cookingNote,
      pickupDistanceKm: pickupDistanceKm,
      tripDistanceKm: tripDistanceKm,
      tripDurationMins: tripDurationMins,
      acceptanceDeadlineAt: acceptanceDeadlineAt,
      vertical: vertical,
      assignedByAdmin: assignedByAdmin,
      customerLocationLink: customerLocationLink,
      displayNumber: displayNumber,
      pickupPin: pickupPin,
    );
  }

  /// The delivery sanitizer flattens some seller fields onto the order root
  /// (`restaurantLandmark`, `restaurantCoverImage`, `restaurantGalleryImages`)
  /// instead of nesting them under the populated seller. This folds them back
  /// in — but only where the nested document didn't already carry a value, so
  /// an empty top-level array never wipes real nested media.
  static Map<String, dynamic> _mergeFlattenedStoreFields(
    Map<String, dynamic> restaurant,
    Map<String, dynamic> order,
  ) {
    bool blank(dynamic v) =>
        v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty);

    final merged = Map<String, dynamic>.from(restaurant);
    for (final (nested, flat) in const [
      ('landmark', 'restaurantLandmark'),
      ('coverImage', 'restaurantCoverImage'),
      ('galleryImages', 'restaurantGalleryImages'),
    ]) {
      if (blank(merged[nested]) && !blank(order[flat])) {
        merged[nested] = order[flat];
      }
    }
    return merged;
  }

  factory DeliveryOrder.fromJson(Map<String, dynamic> json) {
    final pricing = json['pricing'] as Map<String, dynamic>? ?? {};
    final payment = json['payment'] as Map<String, dynamic>? ?? {};
    final deliveryState = json['deliveryState'] as Map<String, dynamic>? ?? {};
    final deliveryVerification =
        json['deliveryVerification'] as Map<String, dynamic>? ?? {};
    final dropOtp =
        deliveryVerification['dropOtp'] as Map<String, dynamic>? ?? {};
    final storeJson = json['restaurantId'];
    final addressJson = json['deliveryAddress'] as Map<String, dynamic>?;

    double n(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    
    return DeliveryOrder(
      id: (json['_id'] ?? '').toString(),
      orderCode: json['order_id'] as String? ?? json['orderId'] as String? ?? '',
      orderStatus: json['orderStatus'] as String? ?? '',
      currentPhase: deliveryState['currentPhase'] as String? ?? 'en_route_to_pickup',
      // `restaurantLandmark` / `restaurantCoverImage` / `restaurantGalleryImages`
      // are flattened onto the order by the delivery sanitizer rather than
      // nested under the populated seller, so they are merged back in here.
      restaurant: storeJson is Map<String, dynamic>
          ? RestaurantInfo.fromJson(_mergeFlattenedStoreFields(storeJson, json))
          : const RestaurantInfo(name: ''),
      deliveryAddress: addressJson != null
          ? DeliveryAddress.fromJson(addressJson)
          : const DeliveryAddress(street: ''),
      items: (json['items'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(OrderItem.fromJson)
          .toList(),
      customerName: json['customerName'] as String? ?? '',
      customerPhone: json['customerPhone'] as String? ?? '',
      customerId: _extractUserId(json['userId']),
      customerPhoto: json['customerPhoto'] as String? ?? json['customerImage'] as String? ?? (json['userId'] is Map ? (json['userId']['profilePhoto'] as String? ?? json['userId']['image'] as String?) : null),
      paymentMethod: json['paymentMethod'] as String? ??
          payment['method'] as String? ??
          'cash',
      paymentStatus: payment['status'] as String? ?? 'cod_pending',
      total: (pricing['total'] as num?)?.toDouble() ?? 0,
      riderEarning: n(json['riderEarning'] ?? json['earnings'] ?? json['earningAmount'] ?? json['deliveryEarning']),
      // The backend sends it at the top level and inside pricing depending on
      // the endpoint; both mean the same thing.
      deliveryTip: n(json['deliveryTip'] ?? pricing['deliveryTip']),
      dropOtpRequired: dropOtp['required'] as bool? ?? false,
      dropOtpVerified: dropOtp['verified'] as bool? ?? false,
      deliveryInstructions:
          json['note'] as String? ?? json['deliveryInstructions'] as String?,
      cookingNote: json['cookingNote'] as String?,
      pickupDistanceKm: n(json['pickupDistanceKm']),
      tripDistanceKm: n(json['tripDistanceKm'] ?? json['distanceKm']),
      tripDurationMins: n(json['tripDurationMins']),
      acceptanceDeadlineAt: json['acceptanceDeadlineAt'] != null
          ? DateTime.tryParse(json['acceptanceDeadlineAt'] as String)
          : null,
      vertical: json['vertical'] as String?,
      customerLocationLink: _mapsLink(
        json['customerLocationLink'] ?? addressJson?['locationLink'],
      ),
      assignedByAdmin: json['assignedByAdmin'] == true ||
          (json['dispatch'] is Map &&
              (json['dispatch'] as Map)['assignedBy'] == 'ADMIN'),
      displayNumber: json['displayNumber']?.toString() ?? '',
      pickupPin: json['pickupPin']?.toString() ?? '',
    );
  }

  /// Parses the flat field set carried by the socket `new_order`/
  /// `new_order_available` events and the FCM `data` payload — as opposed
  /// to [fromJson]'s nested REST-response shape.
  factory DeliveryOrder.fromRealtimePayload(Map<String, dynamic> data) {
    double n(dynamic v) => (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0.0;
    double? nNullable(dynamic v) => v == null ? null : ((v is num) ? v.toDouble() : double.tryParse('$v'));

    List<OrderItem> parseItems(dynamic itemsData) {
      if (itemsData != null) {
        try {
          final List<dynamic> list = itemsData is String ? jsonDecode(itemsData) : itemsData;
          final parsed = list.whereType<Map<String, dynamic>>().map(OrderItem.fromJson).toList();
          if (parsed.isNotEmpty) return parsed;
        } catch (_) {}
      }
      final count = int.tryParse(data['itemCount']?.toString() ?? data['totalItems']?.toString() ?? '0') ?? 0;
      return List.generate(count, (i) => const OrderItem(name: 'Item', price: 0, quantity: 1));
    }

    return DeliveryOrder(
      id: (data['orderMongoId'] ?? data['_id'] ?? '').toString(),
      // `orderId` is the MONGO id on this wire, not the human code — the
      // dispatch push sets `orderId: order._id` and puts the readable
      // "AZ10567" in `orderDisplayId` / `orderNumber`. Reading `orderId` here
      // printed a 24-character ObjectId as the order reference on the alert.
      orderCode: [data['orderDisplayId'], data['orderNumber']]
          .map((v) => v?.toString().trim() ?? '')
          .firstWhere((v) => v.isNotEmpty, orElse: () => ''),
      orderStatus: data['orderStatus'] as String? ?? '',
      currentPhase: data['currentPhase'] as String? ?? 'en_route_to_pickup',
      // The socket event and the FCM push name these differently
      // (`restaurantAddress`/`customerAddress` vs `pickupAddress`/`dropAddress`),
      // and only the socket spelling was read here — so the alert raised from a
      // push showed a restaurant and a customer with no address under either.
      restaurant: RestaurantInfo(
        name: data['restaurantName'] as String? ?? '',
        addressLine1: (data['restaurantAddress'] ?? data['pickupAddress'])
            as String?,
      ),
      deliveryAddress: DeliveryAddress(
        street:
            (data['customerAddress'] ?? data['dropAddress']) as String? ?? '',
      ),
      items: parseItems(data['items']),
      customerName: data['customerName'] as String? ?? '',
      customerPhone: data['customerPhone'] as String? ?? '',
      customerId: _extractUserId(data['userId'] ?? data['customerId']),
      customerPhoto: data['customerPhoto'] as String? ?? data['customerImage'] as String?,
      paymentMethod: data['paymentMethod'] as String? ?? 'cash',
      paymentStatus: data['paymentStatus'] as String? ?? 'cod_pending',
      total: n(data['total']),
      // First NON-ZERO wins, not first present.
      //
      // The dispatch push sends `riderEarning=0` alongside `earnings=50` and
      // `price=50` for the same order. Taking the first key that exists picked
      // the zero and showed the partner "₹0 earning" on a ₹50 job — which is
      // the difference between accepting and declining.
      riderEarning: [data['riderEarning'], data['earnings'], data['price']]
          .map(n)
          .firstWhere((v) => v > 0, orElse: () => 0),
      dropOtpRequired: false,
      dropOtpVerified: false,
      pickupDistanceKm: nNullable(data['pickupDistanceKm']),
      tripDistanceKm: nNullable(data['tripDistanceKm'] ?? data['distance']),
      tripDurationMins: nNullable(data['tripDurationMins']),
      acceptanceDeadlineAt: data['acceptanceDeadlineAt'] != null
          ? DateTime.tryParse(data['acceptanceDeadlineAt'].toString())
          : null,
      vertical: (data['vertical']?.toString().isNotEmpty ?? false)
          ? data['vertical'].toString()
          : null,
      assignedByAdmin: data['assignedByAdmin'] == true,
      customerLocationLink: _mapsLink(data['customerLocationLink']),
      displayNumber: data['displayNumber']?.toString() ?? '',
    );
  }
}
