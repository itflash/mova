import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../pages/home_shell.dart';
import 'app_scope.dart';
import 'app_state.dart';
import 'shadcn_theme.dart';
import 'theme.dart';

class SeedanceNativeApp extends StatefulWidget {
  const SeedanceNativeApp({super.key});

  @override
  State<SeedanceNativeApp> createState() => _SeedanceNativeAppState();
}

class _SeedanceNativeAppState extends State<SeedanceNativeApp>
    with WidgetsBindingObserver {
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state = AppState();
    _state.loadPersistedState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _state.onAppLifecycleChanged(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: Builder(
        builder: (context) => ShadTheme(
          data: shadThemeFor(Theme.of(context).brightness),
          child: MaterialApp(
            title: 'Mova',
            debugShowCheckedModeBanner: false,
            themeMode: ThemeMode.system,
            theme: buildLightTheme(),
            darkTheme: buildDarkTheme(),
            home: const HomeShell(),
          ),
        ),
      ),
    );
  }
}
