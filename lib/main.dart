import 'package:flutter/material.dart';
import 'screens/phone_verification_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Viettel Number Verify',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFFE60012), // Viettel red
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE60012),
          primary: const Color(0xFFE60012),
        ),
        useMaterial3: true,
      ),
      home: const PhoneVerificationScreen(),
    );
  }
}
