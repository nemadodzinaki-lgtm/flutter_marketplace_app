import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../screens/register_screen.dart';

/// Compatibility entry point. The app itself uses LoginScreen under AuthGate.
class Step36LoginScreen extends StatelessWidget {
  const Step36LoginScreen({super.key});
  @override
  Widget build(BuildContext context) => LoginScreen(
    onRegister: () {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (routeContext) =>
              RegisterScreen(onSignIn: () => Navigator.of(routeContext).pop()),
        ),
      );
    },
  );
}
