import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masttersystem/core/background_refresh_mixin.dart';

const _refreshInterval = Duration(seconds: 1);

class _RefreshProbe extends StatefulWidget {
  const _RefreshProbe({super.key, this.onRefresh});

  final FutureOr<void> Function()? onRefresh;

  @override
  State<_RefreshProbe> createState() => _RefreshProbeState();
}

class _RefreshProbeState extends State<_RefreshProbe>
    with BackgroundRefreshMixin<_RefreshProbe> {
  final draftController = TextEditingController();
  int refreshCount = 0;
  int completedCount = 0;

  @override
  Duration get backgroundRefreshInterval => _refreshInterval;

  @override
  Future<void> refreshInBackground() async {
    refreshCount++;
    await widget.onRefresh?.call();
    if (!mounted) return;
    setState(() => completedCount++);
  }

  @override
  void dispose() {
    draftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(controller: draftController);
  }
}

class _TabHost extends StatefulWidget {
  const _TabHost({super.key, required this.firstKey, required this.secondKey});

  final GlobalKey<_RefreshProbeState> firstKey;
  final GlobalKey<_RefreshProbeState> secondKey;

  @override
  State<_TabHost> createState() => _TabHostState();
}

class _TabHostState extends State<_TabHost> {
  int index = 0;

  void select(int value) => setState(() => index = value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          TickerMode(
            enabled: index == 0,
            child: _RefreshProbe(key: widget.firstKey),
          ),
          TickerMode(
            enabled: index == 1,
            child: _RefreshProbe(key: widget.secondKey),
          ),
        ],
      ),
    );
  }
}

void main() {
  void resumeApp() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    if (binding.lifecycleState == AppLifecycleState.paused) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }
    if (binding.lifecycleState == AppLifecycleState.hidden) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  setUp(resumeApp);
  tearDown(resumeApp);

  testWidgets('refresh follows the visible tab and preserves its draft',
      (tester) async {
    final firstKey = GlobalKey<_RefreshProbeState>();
    final secondKey = GlobalKey<_RefreshProbeState>();
    final hostKey = GlobalKey<_TabHostState>();
    await tester.pumpWidget(MaterialApp(
      home: _TabHost(
        key: hostKey,
        firstKey: firstKey,
        secondKey: secondKey,
      ),
    ));

    final firstState = firstKey.currentState!;
    await tester.enterText(
        find.byType(TextField).first, 'Rascunho em andamento');
    await tester.pump(_refreshInterval);
    expect(firstState.refreshCount, 1);
    expect(secondKey.currentState!.refreshCount, 0);
    expect(firstState.draftController.text, 'Rascunho em andamento');

    hostKey.currentState!.select(1);
    await tester.pump();
    await tester.pump(_refreshInterval * 2);
    expect(firstState.refreshCount, 1);
    expect(secondKey.currentState!.refreshCount, 2);

    hostKey.currentState!.select(0);
    await tester.pump();
    await tester.pump(_refreshInterval);
    expect(identical(firstState, firstKey.currentState), isTrue);
    expect(firstState.refreshCount, 2);
    expect(firstState.draftController.text, 'Rascunho em andamento');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an open dialog pauses refresh until the route is current again',
      (tester) async {
    final key = GlobalKey<_RefreshProbeState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: _RefreshProbe(key: key)),
    ));
    final state = key.currentState!;
    unawaited(showDialog<void>(
      context: state.context,
      builder: (_) => const AlertDialog(content: Text('Edição aberta')),
    ));
    await tester.pumpAndSettle();
    await tester.pump(_refreshInterval);
    expect(state.refreshCount, 0);

    Navigator.of(state.context).pop();
    await tester.pumpAndSettle();
    await tester.pump(_refreshInterval);
    expect(state.refreshCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('inactive and paused applications resume refresh when active',
      (tester) async {
    final key = GlobalKey<_RefreshProbeState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: _RefreshProbe(key: key)),
    ));
    final state = key.currentState!;
    for (final lifecycle in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(lifecycle);
      await tester.pump(_refreshInterval);
      expect(state.refreshCount, 0);
    }

    resumeApp();
    await tester.pump(_refreshInterval);
    expect(state.refreshCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a pending refresh never starts a concurrent request',
      (tester) async {
    final pending = Completer<void>();
    final key = GlobalKey<_RefreshProbeState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: _RefreshProbe(key: key, onRefresh: () => pending.future),
      ),
    ));
    final state = key.currentState!;
    await tester.pump(_refreshInterval);
    expect(state.refreshCount, 1);
    expect(state.isRefreshingInBackground, isTrue);
    await tester.pump(_refreshInterval * 3);
    expect(state.refreshCount, 1);

    pending.complete();
    await tester.pump();
    expect(state.isRefreshingInBackground, isFalse);
    expect(state.completedCount, 1);
    await tester.pump(_refreshInterval);
    expect(state.refreshCount, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposing cancels the timer while a request is pending',
      (tester) async {
    final pending = Completer<void>();
    final key = GlobalKey<_RefreshProbeState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: _RefreshProbe(key: key, onRefresh: () => pending.future),
      ),
    ));
    final state = key.currentState!;
    await tester.pump(_refreshInterval);
    expect(state.refreshCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete();
    await tester.pump();
    await tester.pump(_refreshInterval * 3);

    expect(state.refreshCount, 1);
    expect(state.completedCount, 0);
    expect(state.isRefreshingInBackground, isFalse);
    expect(tester.takeException(), isNull);
  });
}
