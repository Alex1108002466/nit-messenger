import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/code_input_field.dart';
import 'login_screen.dart';

class VerifyCodeScreen extends StatefulWidget {
  final String email;

  const VerifyCodeScreen({super.key, required this.email});

  @override
  State<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends State<VerifyCodeScreen> {
  bool _isLoading = false;

  void _handleCodeCompleted(String code) async {
    setState(() => _isLoading = true);

    final result = await AuthService.verifyRegistration(
      email: widget.email,
      code: code,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Регистрация завершена!')),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => route.isFirst,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'])),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Подтверждение'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 32),
            const Icon(Icons.mark_email_read_outlined, size: 64),
            const SizedBox(height: 24),
            Text(
              'Мы отправили код на\n${widget.email}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 48),
            SizedBox(
              height: 56,
              child: Center(
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : CodeInputField(onCompleted: _handleCodeCompleted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}