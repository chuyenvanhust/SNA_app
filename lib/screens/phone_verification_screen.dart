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
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final ViettelApiService _apiService = ViettelApiService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  // Used for debugging/tracking API flow steps (can be displayed in UI if needed)
  // ignore: unused_field
  String _currentStep = '';

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Handle traditional sign in with phone and password
  Future<void> _handleSignIn() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _currentStep = 'Signing in...';
      });

      String phoneNumber = _phoneController.text;
      // Password will be used when traditional authentication API is implemented
      // ignore: unused_local_variable
      String password = _passwordController.text;
      print('Traditional sign in for phone: $phoneNumber');

      try {
        // TODO: Implement traditional authentication API call here
        // This would typically call a different endpoint that requires password
        await Future.delayed(const Duration(seconds: 2)); // Simulated API call

        setState(() {
          _isLoading = false;
          _currentStep = '';
        });

        // For now, show success (replace with actual API logic)
        if (mounted) {
          _showErrorDialog(
            'Traditional sign in with password is not implemented yet. Please use "Sign In with SNA".',
          );
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

  /// Handle Silent Network Authentication (SNA) - no password required
  Future<void> _handleSignInWithSNA() async {
    // Only validate phone number for SNA
    if (_phoneController.text.isEmpty || _phoneController.text.length < 9) {
      _showErrorDialog('Please enter a valid phone number');
      return;
    }

    setState(() {
      _isLoading = true;
      _currentStep = 'Initializing SNA...';
    });

    String phoneNumber = _phoneController.text;
    print('Starting SNA verification for phone number: $phoneNumber');

    try {
      // Update UI with each step
      setState(() => _currentStep = 'Step 1: Getting authorization...');
      await Future.delayed(const Duration(milliseconds: 500));

      // Call the 3-step API flow for SNA
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
                  const Text(
                    'Sign in with your credentials or use SNA',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 25),

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
                  const SizedBox(height: 10),

                  // Password Input Field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Enter your password',
                      prefixIcon: const Icon(
                        Icons.lock,
                        color: Color(0xFFE60012),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
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
                        return 'Please enter your password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Sign In Button (Traditional)
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
                  const SizedBox(height: 10),

                  // // Divider with "OR"
                  // Row(
                  //   children: [
                  //     Expanded(
                  //       child: Divider(
                  //         color: Colors.grey.shade400,
                  //         thickness: 1,
                  //       ),
                  //     ),
                  //     Padding(
                  //       padding: const EdgeInsets.symmetric(horizontal: 16),
                  //       child: Text(
                  //         'OR',
                  //         style: TextStyle(
                  //           color: Colors.grey.shade600,
                  //           fontWeight: FontWeight.w500,
                  //           fontSize: 14,
                  //         ),
                  //       ),
                  //     ),
                  //     Expanded(
                  //       child: Divider(
                  //         color: Colors.grey.shade400,
                  //         thickness: 1,
                  //       ),
                  //     ),
                  //   ],
                  // ),
                  // const SizedBox(height: 20),

                  // Sign In with SNA Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _handleSignInWithSNA,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE60012),
                        side: BorderSide(
                          color: _isLoading
                              ? Colors.grey.shade300
                              : const Color(0xFFE60012),
                          width: 2,
                        ),
                        disabledForegroundColor: Colors.grey,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.network_cell, size: 24),
                      label: const Text(
                        'Sign In with SNA',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Info text about SNA
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'SNA (Silent Network Authentication) verifies your phone number without a password',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
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
