import 'package:flutter_marketplace_app/screens/chat_screen.dart';
import 'package:flutter/services.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:flutter_marketplace_app/main.dart';
import 'package:flutter_marketplace_app/screens/advanced_search_screen.dart';
import 'package:flutter_marketplace_app/screens/create_listing_screen.dart';
import 'package:flutter_marketplace_app/screens/favourites_screen.dart';
import 'package:flutter_marketplace_app/screens/my_listings_screen.dart';
import 'package:flutter_marketplace_app/screens/admin_user_management_screen.dart';
import 'package:flutter_marketplace_app/screens/admin_advertisements_screen.dart';
import 'package:flutter_marketplace_app/screens/admin_reports_management_screen.dart';
import 'package:flutter_marketplace_app/theme/marketplace_theme.dart';
import 'package:flutter_marketplace_app/screens/admin_dashboard_screen.dart';
import 'package:flutter_marketplace_app/screens/login_screen.dart';
import 'package:flutter_marketplace_app/screens/marketplace_shell.dart';
import 'package:flutter_marketplace_app/screens/register_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    final sdk = Platform.environment['FLUTTER_ROOT'];
    if (sdk == null) return;
    final font = File(
      '$sdk/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
    );
    if (font.existsSync()) {
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  late Supabase supabase;
  late Map<String, dynamic>? profile;
  late bool rejectLogin;
  late bool failProfile;
  late bool confirmEmail;
  Completer<void>? profileDelay;
  Completer<void>? sendDelay;
  late List<String> sentMessages;

  Map<String, dynamic> session() {
    final payload = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'sub': 'test-account',
              'exp':
                  DateTime.now()
                      .add(const Duration(hours: 1))
                      .millisecondsSinceEpoch ~/
                  1000,
            }),
          ),
        )
        .replaceAll('=', '');
    return {
      'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.signature',
      'refresh_token': 'test-refresh-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': 'test-account',
        'aud': 'authenticated',
        'email': 'test@example.com',
        'app_metadata': {},
        // Routing must use the database even when metadata disagrees.
        'user_metadata': {'role': 'admin'},
        'created_at': '2026-01-01T00:00:00Z',
      },
    };
  }

  setUp(() async {
    profile = {
      'first_name': 'Test',
      'role': 'user',
      'account_status': 'active',
    };
    rejectLogin = false;
    failProfile = false;
    confirmEmail = true;
    profileDelay = null;
    sendDelay = null;
    sentMessages = [];
    supabase = await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'test-key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
        authFlowType: AuthFlowType.implicit,
        pkceAsyncStorage: _TestAuthStorage(),
      ),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      realtimeClientOptions: RealtimeClientOptions(
        connectionCloseTimeout: Duration.zero,
        disconnectOnEmptyChannelsAfter: Duration.zero,
        transport: (uri, headers) {
          final channel = StreamChannelController<String>();
          channel.foreign.stream.listen((raw) {
            final message = jsonDecode(raw);
            final reply = {'status': 'ok', 'response': <String, dynamic>{}};
            channel.foreign.sink.add(
              jsonEncode(
                message is List
                    ? [message[0], message[1], message[2], 'phx_reply', reply]
                    : {
                        'event': 'phx_reply',
                        'topic': message['topic'],
                        'ref': message['ref'],
                        'payload': reply,
                      },
              ),
            );
          }, onDone: () => channel.foreign.sink.close());
          return _TestWebSocket(channel.local);
        },
      ),
      httpClient: MockClient((request) async {
        Object? body;
        var status = 200;
        switch (request.url.path) {
          case '/auth/v1/token':
            body = rejectLogin
                ? {
                    'msg': 'Invalid login credentials',
                    'code': 'invalid_credentials',
                  }
                : session();
            status = rejectLogin ? 400 : 200;
          case '/auth/v1/signup':
            body = confirmEmail ? session()['user'] : session();
          case '/auth/v1/logout':
            body = <String, dynamic>{};
          case '/rest/v1/conversations':
            body = request.url.queryParameters['id'] == 'eq.test-conversation'
                ? {
                    'id': 'test-conversation',
                    'buyer_id': 'test-account',
                    'seller_id': 'other-account',
                    'listings': {'title': 'Test advertisement'},
                  }
                : <Object>[];
          case '/rest/v1/messages':
            if (request.method == 'POST') {
              sentMessages.add(
                (jsonDecode(request.body) as Map)['message_text'] as String,
              );
              await sendDelay?.future;
            }
            body = <Object>[];
          case '/rest/v1/profiles':
            await profileDelay?.future;
            body = failProfile
                ? {
                    'message': 'Profile temporarily unavailable',
                    'code': 'test_error',
                  }
                : profile;
            status = failProfile ? 503 : 200;
          case '/rest/v1/rpc/admin_list_marketplace_users':
          case '/rest/v1/rpc/admin_list_marketplace_advertisements':
            body = <String, dynamic>{};
          case '/rest/v1/rpc/step30_admin_dashboard_stats':
            body = <String, dynamic>{};
          default:
            body = <Object>[];
        }
        return http.Response(
          jsonEncode(body),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  tearDown(() async => supabase.dispose());

  Future<void> openApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
  }

  Future<void> login(WidgetTester tester) async {
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'test@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'signed-out launch shows sign-in and registration returns to it',
    (tester) async {
      await openApp(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(RegisterScreen), findsNothing);
      await tester.tap(find.text("Don't have an account? Create Account"));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsOneWidget);
      await tester.tap(find.text('Already have an account? Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.byType(LoginScreen))).canPop(),
        isFalse,
      );
      await disposeApp(tester);
    },
  );

  for (final role in ['user', 'admin']) {
    testWidgets(
      '$role login opens its destination and logout returns to sign-in',
      (tester) async {
        profile!['role'] = role;
        await openApp(tester);
        await login(tester);
        expect(
          find.byType(
            role == 'admin' ? AdminDashboardScreen : MarketplaceShell,
          ),
          findsOneWidget,
        );
        expect(find.byType(RegisterScreen), findsNothing);
        expect(find.byType(LoginScreen), findsNothing);
        await tester.tap(find.byIcon(Icons.logout_rounded).first);
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(find.byType(RegisterScreen), findsNothing);
        await disposeApp(tester);
      },
    );
  }

  testWidgets('invalid credentials stay on sign-in with an error', (
    tester,
  ) async {
    rejectLogin = true;
    await openApp(tester);
    await login(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Invalid login credentials'), findsOneWidget);
    await disposeApp(tester);
  });

  for (final problem in ['missing', 'inactive', 'unknown role', 'network']) {
    testWidgets(
      '$problem profile does not bounce to registration or allow access',
      (tester) async {
        if (problem == 'missing') profile = null;
        if (problem == 'inactive') profile!['account_status'] = 'suspended';
        if (problem == 'unknown role') profile!['role'] = 'unexpected';
        failProfile = problem == 'network';
        await openApp(tester);
        await login(tester);
        expect(find.text('Try Again'), findsOneWidget);
        expect(find.byType(RegisterScreen), findsNothing);
        expect(find.byType(MarketplaceShell), findsNothing);
        expect(find.byType(AdminDashboardScreen), findsNothing);
        expect(supabase.client.auth.currentSession, isNotNull);
        if (problem == 'network') {
          failProfile = false;
          await tester.tap(find.text('Try Again'));
          await tester.pumpAndSettle();
          expect(find.byType(MarketplaceShell), findsOneWidget);
        } else {
          await tester.tap(find.text('Sign Out'));
          await tester.pumpAndSettle();
          expect(find.byType(LoginScreen), findsOneWidget);
        }
        await disposeApp(tester);
      },
    );
  }

  for (final confirmation in [true, false]) {
    testWidgets('registration handles email confirmation = $confirmation', (
      tester,
    ) async {
      confirmEmail = confirmation;
      await openApp(tester);
      await tester.tap(find.text("Don't have an account? Create Account"));
      await tester.pumpAndSettle();
      final values = [
        'Test',
        'User',
        'test@example.com',
        '0821234567',
        '9001015009087',
        'test-password',
        'test-password',
      ];
      for (var i = 0; i < values.length; i++) {
        await tester.enterText(find.byType(TextFormField).at(i), values[i]);
      }
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(
        find.byType(confirmation ? LoginScreen : MarketplaceShell),
        findsOneWidget,
      );
      expect(find.byType(RegisterScreen), findsNothing);
      await disposeApp(tester);
    });
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/ui-previews')..createSync(recursive: true);
      File('${dir.path}/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('phone login and keyboard layout remain usable', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: key, child: const MyApp()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'login-phone');
    await tester.ensureVisible(find.byType(TextFormField).at(1));
    await tester.tap(find.byType(TextFormField).at(1));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign In'));
    expect(tester.takeException(), isNull);
    expect(find.text('Sign In').hitTestable(), findsOneWidget);
    tester.view.resetViewInsets();
    await disposeApp(tester);
  });

  for (final role in ['user', 'admin']) {
    testWidgets('$role destination works at 320px with enlarged text', (
      tester,
    ) async {
      profile!['role'] = role;
      await supabase.client.auth.signInWithPassword(
        email: 'test@example.com',
        password: 'test-password',
      );
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: key, child: const MyApp()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byType(role == 'admin' ? AdminDashboardScreen : MarketplaceShell),
        findsOneWidget,
      );
      await capture(tester, key, '$role-phone-large-text');
      if (role == 'user') {
        await tester.tap(find.byType(NavigationDestination).at(2));
        await tester.pumpAndSettle();
        expect(find.byType(CreateListingScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      if (role == 'admin') {
        expect(find.byType(MarketplaceShell), findsNothing);
        await tester.drag(find.byType(ListView).first, const Offset(0, -800));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await disposeApp(tester);
    });
  }

  final screens = <String, Widget>{
    'explore': const AdvancedSearchScreen(),
    'post': const CreateListingScreen(),
    'favourites': const FavouritesScreen(),
    'my-listings': const MyListingsScreen(),
    'admin-users': const AdminUserManagementScreen(),
    'admin-advertisements': const AdminAdvertisementsScreen(),
    'admin-reports': const AdminReportsManagementScreen(),
  };
  for (final entry in screens.entries) {
    testWidgets('${entry.key} fits a narrow phone', (tester) async {
      profile!['role'] = entry.key.startsWith('admin') ? 'admin' : 'user';
      await supabase.client.auth.signInWithPassword(
        email: 'test@example.com',
        password: 'test-password',
      );
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(theme: MarketplaceTheme.light, home: entry.value),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (entry.key == 'explore') {
        await tester.tap(find.text('Advanced filters'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await disposeApp(tester);
    });
  }

  testWidgets(
    'sending a message preserves a newer draft typed while uploading',
    (tester) async {
      await supabase.client.auth.signInWithPassword(
        email: 'test@example.com',
        password: 'test-password',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: MarketplaceTheme.light,
          home: const ChatScreen(conversationId: 'test-conversation'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      sendDelay = Completer<void>();
      await tester.enterText(find.byType(TextField), 'First message');
      await tester.tap(find.byTooltip('Send message'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Next draft');
      sendDelay!.complete();
      await tester.pumpAndSettle();
      expect(sentMessages, ['First message']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Next draft',
      );
      expect(tester.takeException(), isNull);
      await disposeApp(tester);
    },
  );

  testWidgets('an existing session opens its destination on restart', (
    tester,
  ) async {
    profile!['role'] = 'admin';
    await supabase.client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test-password',
    );
    await openApp(tester);
    expect(find.byType(AdminDashboardScreen), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets('late profile response cannot reopen a signed-out account', (
    tester,
  ) async {
    await openApp(tester);
    profileDelay = Completer<void>();
    await supabase.client.auth.signInWithPassword(
      email: 'test@example.com',
      password: 'test-password',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await supabase.client.auth.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    profileDelay!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(MarketplaceShell), findsNothing);
    await disposeApp(tester);
  });
}

// In-memory realtime connection keeps these auth tests entirely offline.
class _TestWebSocket extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  _TestWebSocket(this.channel);
  final StreamChannel<String> channel;
  @override
  Stream<dynamic> get stream => channel.stream;
  @override
  late final WebSocketSink sink = _TestWebSocketSink(channel.sink);
  @override
  Future<void> get ready => Future.value();
  @override
  String? get protocol => null;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
}

class _TestWebSocketSink implements WebSocketSink {
  _TestWebSocketSink(this.sink);
  final StreamSink<String> sink;
  @override
  void add(dynamic data) => sink.add(data as String);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      sink.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<dynamic> stream) =>
      sink.addStream(stream.cast<String>());
  @override
  Future<void> close([int? closeCode, String? closeReason]) => sink.close();
  @override
  Future<void> get done => sink.done;
}

class _TestAuthStorage extends GotrueAsyncStorage {
  const _TestAuthStorage();
  @override
  Future<String?> getItem({required String key}) async => null;
  @override
  Future<void> setItem({required String key, required String value}) async {}
  @override
  Future<void> removeItem({required String key}) async {}
}
