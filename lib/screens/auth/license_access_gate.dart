import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/license_provider.dart';
import 'activation_screen.dart';

/// Cobre também as páginas e os diálogos abertos no Navigator.
class LicenseAccessGate extends StatelessWidget {
  const LicenseAccessGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final license = context.watch<LicenseProvider>();
    return Stack(
      fit: StackFit.expand,
      children: [
        if (license.isActivated)
          // Uma verificação pendente esconde o conteúdo, mas mantém o Navigator
          // e os formulários montados. Remover esse filho reiniciaria a sessão
          // visual na página inicial ao voltar de outro aplicativo.
          Offstage(
            offstage: license.isLoading,
            child: TickerMode(
              enabled: !license.isLoading,
              child: ExcludeFocus(
                excluding: license.isLoading,
                child: child,
              ),
            ),
          ),
        if (license.isLoading)
          const Scaffold(body: Center(child: CircularProgressIndicator()))
        else if (!license.isActivated)
          Overlay(
            initialEntries: [
              OverlayEntry(builder: (_) => const ActivationScreen()),
            ],
          ),
      ],
    );
  }
}
