import 'package:flutter/material.dart';
import 'package:sohr_delivery_partner/core/constants/app_constants.dart';

class AppTheme {
  // Define core colors
  static const Color primaryColor = Color(0xFFC4801C); // Brand golden
  static const Color darkBackground = Color(0xFF121212);
  static const Color lightBackground = Color(0xFFF8F9FA);

  static const Color darkCard = Color(0xFF1E1E1E);
  static const Color lightCard = Colors.white;

  static const Color darkNavBackground = Color(0xFF1C1C1E);
  static const Color lightNavBackground = Color(0xFF2C2C2E);

  static ThemeData get lightTheme {
    return ThemeData(
      fontFamily: AppConstants.appFontFamily,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: lightBackground,
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: Color(0xFFE0A64F), // Lighter golden accent
        surface: lightCard,
        onSurface: Colors.black,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black),
        titleTextStyle: TextStyle(
          color: Colors.black,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: lightNavBackground,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      fontFamily: AppConstants.appFontFamily,
      primaryColor: primaryColor,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: Color(0xFFE0A64F),
        surface: darkCard,
        onSurface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkNavBackground,
      ),
    );
  }
}
