import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminTestScreen extends StatefulWidget {
  const AdminTestScreen({super.key});

  @override
  State<AdminTestScreen> createState() => _AdminTestScreenState();
}

class _AdminTestScreenState extends State<AdminTestScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  bool isLoading = false;
  String resultMessage = '';

  Future<void> createCoach() async {
    setState(() {
      isLoading = true;
      resultMessage = '';
    });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'create-coach',
        body: {
          'email': emailController.text.trim(),
          'password': passwordController.text.trim(),
          'fullName': nameController.text.trim(),
        },
      );

      setState(() {
        resultMessage = 'Success: ${response.data}';
      });
    } catch (e) {
      setState(() {
        resultMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Coach (Admin Only)')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Coach Full Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Coach Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: 'Coach Password'),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                  onPressed: createCoach,
                  child: const Text('Create Coach'),
                ),
            const SizedBox(height: 20),
            Text(resultMessage),
          ],
        ),
      ),
    );
  }
}
