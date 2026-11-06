import 'package:url_launcher/url_launcher.dart';

/// The business behind SOHR, as payment partners and app stores need to see it.
/// The same details are on https://sohr.in, so keep the two in step.
abstract final class LegalInfo {
  static const legalName = 'SOHR-SOUL OF HUNGERR RESTAURANT PRIVATE LIMITED';
  static const brand = 'SOHR by Vyas Ji';
  static const address =
      '48, 32, 3B Tashkent Marg, Civil Lines, Prayagraj, Uttar Pradesh 211001, India';
  static const phone = '+91 93052 04140';
  static const phoneUri = 'tel:+919305204140';
  static const website = 'https://sohr.in';

  /// Public pages on the website, as (title, path).
  static const pages = [
    ('About Us', '/about'),
    ('Contact Us', '/contact'),
    ('Terms & Conditions', '/terms'),
    ('Privacy Policy', '/privacy-policy'),
    ('Refund & Cancellation Policy', '/refund-policy'),
    ('Shipping & Delivery Policy', '/shipping-policy'),
  ];

  static Future<bool> open(String pathOrUri) => launchUrl(
        Uri.parse(pathOrUri.startsWith('/') ? '$website$pathOrUri' : pathOrUri),
        mode: LaunchMode.externalApplication,
      );
}
