import 'dart:io';

import 'package:masttersystem/core/licensing/license_code.dart';

void main(List<String> arguments) {
  final isInteractive = arguments.isEmpty;
  String? informedCode;

  if (isInteractive) {
    print('==========================================');
    print('      GERADOR DE LICENCA MASTTERSYSTEM');
    print('==========================================');
    print('');
    stdout.write('Digite o codigo de 12 numeros do computador: ');
    informedCode = stdin.readLineSync();
  } else if (arguments.length == 1) {
    informedCode = arguments.first;
  } else {
    print('Uso: generate_license CODIGO-DO-COMPUTADOR');
    exitCode = 64;
    return;
  }

  final installation = (informedCode ?? '').replaceAll(RegExp(r'\D'), '');
  print('');
  if (installation.length != 12) {
    print('ERRO: informe exatamente os 12 numeros do codigo do computador.');
    exitCode = 65;
    if (isInteractive) {
      _waitBeforeClosing();
    }
    return;
  }

  final activation = activationCodeForInstallation(installation);
  print('Computador: ${formatInstallationCode(installation)}');
  print('Chave de ativacao: $activation');

  if (isInteractive) {
    _waitBeforeClosing();
  }
}

void _waitBeforeClosing() {
  print('');
  stdout.write('Pressione ENTER para fechar...');
  stdin.readLineSync();
}
