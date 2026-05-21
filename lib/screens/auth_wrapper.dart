import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/app_state.dart';
import 'auth_screen.dart';
import '../app.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  User? _previousUser;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = snapshot.data;
        if (_previousUser != null && user == null) {
          context.read<AppState>().clearSession();
        }
        _previousUser = user;

        if (user != null) {
          return InitializerScreen(key: ValueKey(user.uid));
        }

        return const AuthScreen();
      },
    );
  }
}

Future<void> _signOut(BuildContext context) async {
  await AuthService().signOut(
    onBeforeSignOut: () async => context.read<AppState>().clearSession(),
  );
}

class InitializerScreen extends StatefulWidget {
  const InitializerScreen({super.key});
  @override
  State<InitializerScreen> createState() => _InitializerScreenState();
}

class _InitializerScreenState extends State<InitializerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        context.read<AppState>().initializeUser(user);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    
    if (state.isLoadingUser || state.currentUser == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              if (state.backendError != null) ...[
                Text(state.backendError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _signOut(context),
                  child: const Text("Sign Out & Retry"),
                )
              ] else
                const Text("Connecting securely..."),
            ],
          ),
        ),
      );
    }
    
    return const AppShell();
  }
}
