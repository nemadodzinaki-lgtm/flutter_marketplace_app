import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme/marketplace_theme.dart';
import 'step36/step36_entry_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://gxfsfejamthhflsazpzp.supabase.co',
    publishableKey: 'sb_publishable_79kl7s4jAjv3WNYlwj18Ow_NuU0_v3_',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Community Marketplace',
      theme: MarketplaceTheme.light,
      home: const Step36EntryGate(),
    );
  }
}
