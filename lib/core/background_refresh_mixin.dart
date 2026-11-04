import 'dart:async';

import 'package:flutter/material.dart';

/// Atualiza os dados da tela visível sem recriar o widget nem apagar
/// formulários em andamento. Diálogos e telas que não estão em primeiro
/// plano pausam a consulta automaticamente.
mixin BackgroundRefreshMixin<T extends StatefulWidget> on State<T> {
  Timer? _backgroundRefreshTimer;
  bool _backgroundRefreshRunning = false;

  /// Permite que a tela evite mostrar novamente seu indicador de carga
  /// durante uma sincronização automática.
  bool get isRefreshingInBackground => _backgroundRefreshRunning;

  Duration get backgroundRefreshInterval => const Duration(seconds: 5);

  /// Atualiza somente os dados, preservando os controles e rascunhos da tela.
  ///
  /// Como a operação pode terminar depois que a tela for fechada, implementações
  /// assíncronas devem verificar [mounted] antes de usar o contexto ou setState.
  FutureOr<void> refreshInBackground();

  @override
  void initState() {
    super.initState();
    _backgroundRefreshTimer = Timer.periodic(
      backgroundRefreshInterval,
      (_) => _runBackgroundRefresh(),
    );
  }

  Future<void> _runBackgroundRefresh() async {
    if (!mounted || _backgroundRefreshRunning) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    // Telas mantidas no IndexedStack continuam montadas, mas somente a aba
    // selecionada deve consultar seus dados automaticamente.
    if (!TickerMode.valuesOf(context).enabled) return;
    if (ModalRoute.of(context)?.isCurrent == false) return;

    _backgroundRefreshRunning = true;
    try {
      await refreshInBackground();
    } catch (error, stackTrace) {
      debugPrint('Falha na atualização em segundo plano: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _backgroundRefreshRunning = false;
    }
  }

  @override
  void dispose() {
    _backgroundRefreshTimer?.cancel();
    super.dispose();
  }
}
