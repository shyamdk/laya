import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/providers.dart';
import 'features/auth/auth_screen.dart';
import 'features/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(const _MisconfiguredApp());
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: LayaApp()));
}

class LayaApp extends ConsumerWidget {
  const LayaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild on sign-in / sign-out.
    ref.watch(authStateProvider);
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      title: 'Laya',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F3A5F)),
        cardTheme: const CardThemeData(elevation: 1),
      ),
      home: session == null ? const AuthScreen() : const HomeScreen(),
    );
  }
}

/// Shown when the app was built without Supabase credentials, instead of
/// failing with an opaque crash.
class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.settings, size: 48),
                SizedBox(height: 16),
                Text('Supabase is not configured',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                SelectableText(
                  'Run with:\n\n'
                  'flutter run -d chrome \\\n'
                  '  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \\\n'
                  '  --dart-define=SUPABASE_ANON_KEY=<anon key from `supabase status`>',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
