import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/viettel_api_service.dart';
import '../widgets/debug_terminal.dart';
import 'welcome_screen.dart';

class PhoneVerificationScreen extends StatefulWidget {
  const PhoneVerificationScreen({super.key});

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final ViettelApiService _apiService = ViettelApiService();

  bool _isLoading = false;
  String _currentStep = '';

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  /// Handle sign in button press - triggers 3-step API flow
  Future<void> _handleSignIn() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _currentStep = 'Initializing...';
      });

      String phoneNumber = _phoneController.text;
      print('Starting verification for phone number: $phoneNumber');

      try {
        // Update UI with each step
        setState(() => _currentStep = 'Step 1: Getting authorization...');
        await Future.delayed(const Duration(milliseconds: 500));

        // Call the 3-step API flow
        final result = await _apiService.verifyPhoneNumber(phoneNumber);

        setState(() {
          _isLoading = false;
          _currentStep = '';
        });

        if (result.success && result.data?.devicePhoneNumberVerified == true) {
          // Success - Navigate to welcome screen
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => WelcomeScreen(phoneNumber: phoneNumber),
              ),
            );
          }
        } else {
          // Failed - Show error dialog
          if (mounted) {
            _showErrorDialog(
              result.message.isNotEmpty
                  ? result.message
                  : 'The phone number not match with the device',
            );
          }
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
          _currentStep = '';
        });

        if (mounted) {
          _showErrorDialog('An error occurred: ${e.toString()}');
        }
      }
    }
  }

  /// Show error dialog to user
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Text('Verification Failed'),
            ],
          ),
          content: Text(message, style: const TextStyle(fontSize: 16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'OK',
                style: TextStyle(
                  color: Color(0xFFE60012),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Phone Verification',
          style: TextStyle(
            color: Color(0xFFE60012),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          // Debug Terminal Button
          IconButton(
            icon: const Icon(Icons.terminal, color: Color(0xFFE60012)),
            tooltip: 'Debug Terminal',
            onPressed: () => showDebugTerminal(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Viettel Logo
                  Image.asset(
                    'lib/images/Viettel_img.png',
                    width: 500,
                    height: 200,
                    fit: BoxFit.contain,
                  ),
                  // Welcome Text
                  const Text(
                    'Welcome',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE60012), // Viettel red color
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Please enter your phone number to continue',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // Phone Number Input Field
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      hintText: 'Enter your phone number',
                      prefixIcon: const Icon(
                        Icons.phone,
                        color: Color(0xFFE60012),
                      ),
                      prefixText: '+84 ',
                      prefixStyle: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.grey),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFE60012),
                          width: 2,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.red),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your phone number';
                      }
                      if (value.length < 9) {
                        return 'Please enter a valid phone number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Sign In Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleSignIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE60012), // Viettel red
                        foregroundColor: Colors.white,
                        elevation: 2,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'Sign In',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // // Loading Status
                  // if (_isLoading)
                  //   Column(
                  //     children: [
                  //       Text(
                  //         _currentStep,
                  //         style: TextStyle(
                  //           fontSize: 14,
                  //           color: Colors.grey.shade600,
                  //           fontStyle: FontStyle.italic,
                  //         ),
                  //         textAlign: TextAlign.center,
                  //       ),
                  //       const SizedBox(height: 8),
                  //       LinearProgressIndicator(
                  //         backgroundColor: Colors.grey.shade200,
                  //         valueColor: const AlwaysStoppedAnimation<Color>(
                  //           Color(0xFFE60012),
                  //         ),
                  //       ),
                  //     ],
                  //   ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
