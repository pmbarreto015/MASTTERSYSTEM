import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'servidor_banco.dart' as banco;

/// Mantém a porta do Render disponível até a importação do banco por SSH/SCP.
/// O arquivo deve ser enviado com outro nome e renomeado ao terminar o upload.
Future<void> main(List<String> arguments) async {
  try {
    final port = int.tryParse(Platform.environment['PORT'] ?? '10000');
    if (port == null || port < 1024 || port > 65535) {
      throw const FormatException('PORT deve estar entre 1024 e 65535.');
    }
    final token =
        (Platform.environment['MATTERDI_DATABASE_TOKEN'] ?? '').trim();
    if (token.length < 24 || token.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException(
        'Configure MATTERDI_DATABASE_TOKEN com pelo menos 24 caracteres.',
      );
    }
    final configuredPath = Platform.environment['MATTERDI_DATABASE_PATH'];
    final databasePath = configuredPath == null || configuredPath.trim().isEmpty
        ? '/var/data/matterdi_sistem.db'
        : configuredPath.trim();
    final databaseFile = File(databasePath);
    if (!await databaseFile.exists() &&
        !await _waitForImport(databaseFile, port)) {
      return;
    }
    await banco.main([
      '--database',
      databasePath,
      '--bind',
      '0.0.0.0',
      '--port',
      '$port',
    ]);
  } catch (error) {
    stderr.writeln('Não foi possível iniciar o servidor Render: $error');
    exitCode = 1;
  }
}

Future<bool> _waitForImport(File databaseFile, int port) async {
  final ready = Completer<bool>();
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  HttpServer? server;
  Timer? poll;
  var checking = false;
  var stopped = false;
  var imported = false;

  Future<void> checkFile() async {
    if (checking || ready.isCompleted) return;
    checking = true;
    try {
      if (await databaseFile.exists() && !ready.isCompleted) {
        ready.complete(true);
      }
    } catch (error, stack) {
      if (!ready.isCompleted) ready.completeError(error, stack);
    } finally {
      checking = false;
    }
  }

  try {
    for (final signal in [
      ProcessSignal.sigint,
      if (!Platform.isWindows) ProcessSignal.sigterm,
    ]) {
      subscriptions.add(signal.watch().listen((_) {
        stopped = true;
        if (!ready.isCompleted) ready.complete(false);
      }));
    }
    server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    server.listen(
      (request) => unawaited(_respondWaiting(request)),
      onError: (Object error, StackTrace stack) {
        if (!ready.isCompleted) ready.completeError(error, stack);
      },
      onDone: () {
        if (!ready.isCompleted) ready.complete(false);
      },
    );
    stdout.writeln('Servidor aguardando importação do banco por SSH/SCP.');
    poll = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(checkFile());
    });
    await checkFile();
    imported = await ready.future;
  } finally {
    poll?.cancel();
    await server?.close(force: true);
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
  return imported && !stopped;
}

Future<void> _respondWaiting(HttpRequest request) async {
  try {
    request.response
      ..statusCode = HttpStatus.serviceUnavailable
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..write(jsonEncode({
        'error': 'O servidor está aguardando importação do banco de dados.',
      }));
    await request.response.close();
  } catch (_) {
    // Um cliente desconectado não encerra a espera pela importação.
  }
}
