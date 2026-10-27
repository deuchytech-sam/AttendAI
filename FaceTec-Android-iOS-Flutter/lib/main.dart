import 'package:flutter/material.dart';
import 'package:face_liveness_verification/face_liveness_verification.dart';
import 'liveness_verification_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AttendAI - Face Liveness Verification',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'AttendAI - Face Liveness Verification'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'Choose Liveness Verification Method:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: const Icon(Icons.verified_user),
              label: const Text('Face Liveness Verification'),
              onPressed: () {
                _startNewLivenessVerification();
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(300, 50),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text('Enroll New Face'),
              onPressed: () {
                _startEnrollment();
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(300, 50),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.face_retouching_natural),
              label: const Text('Liveness Demo Only'),
              onPressed: () {
                _startLivenessDemo();
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(300, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startNewLivenessVerification() async {
    // Navigate to the new liveness verification screen
    // This requires an enrolled template - for demo, we'll just show an error
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verification Mode'),
        content: const Text(
          'This mode requires a previously enrolled face template. '
          'Please use "Enroll New Face" first to create a template, '
          'then use "Face Liveness Verification" to verify against it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _startEnrollment() async {
    final faceIdController = TextEditingController();
    final faceId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enroll New Face'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter a unique Face ID for enrollment:'),
            const SizedBox(height: 16),
            TextField(
              controller: faceIdController,
              decoration: const InputDecoration(
                labelText: 'Face ID',
                hintText: 'e.g., user_001',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (faceIdController.text.trim().isNotEmpty) {
                Navigator.of(context).pop(faceIdController.text.trim());
              }
            },
            child: const Text('Enroll'),
          ),
        ],
      ),
    );

    if (faceId != null && faceId.isNotEmpty) {
      // Navigate to enrollment screen
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => LivenessVerificationScreen(
            enrolledFaceId: faceId,
          ),
        ),
      );

      if (result != null && result is FaceLivenessMatchResult && result.enrolledTemplate != null) {
        // Show success and store the template
        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Enrollment Successful'),
                ],
              ),
              content: Text('Face template enrolled for: ${result.faceId}'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    }
  }

  Future<void> _startLivenessDemo() async {
    // Navigate to liveness demo screen (no enrollment/verification, just liveness check)
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const LivenessVerificationScreen(),
      ),
    );
  }
}