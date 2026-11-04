import 'ponto_model.dart';

/// Resumo dos valores registrados, sem aplicar regras adicionais de jornada.
class PontoReport {
  PontoReport({
    required this.employeeId,
    required DateTime start,
    required DateTime end,
    required Iterable<PontoModel> records,
  })  : start = DateTime(start.year, start.month, start.day),
        end = DateTime(end.year, end.month, end.day) {
    if (this.end.isBefore(this.start)) {
      throw ArgumentError(
          'A data final deve ser igual ou posterior à inicial.');
    }
    final exclusiveEnd = DateTime(end.year, end.month, end.day + 1);
    pontos = List.unmodifiable(records.where((ponto) {
      final day = DateTime(ponto.data.year, ponto.data.month, ponto.data.day);
      return ponto.employeeId == employeeId &&
          !day.isBefore(this.start) &&
          day.isBefore(exclusiveEnd);
    }).toList()
      ..sort((a, b) {
        final byDate = a.data.compareTo(b.data);
        return byDate != 0 ? byDate : (a.id ?? 0).compareTo(b.id ?? 0);
      }));
  }

  final int employeeId;
  final DateTime start;
  final DateTime end;
  late final List<PontoModel> pontos;

  int get diasRegistrados => pontos
      .map((ponto) =>
          DateTime(ponto.data.year, ponto.data.month, ponto.data.day))
      .toSet()
      .length;

  int get registrosAbertos => pontos
      .where((ponto) =>
          ponto.entrada1 == null ||
          ponto.saida1 == null ||
          ponto.entrada2 == null ||
          ponto.saida2 == null)
      .length;

  double get totalHoras =>
      pontos.fold(0.0, (total, ponto) => total + ponto.horasTrabalhadas);

  double get totalExtras =>
      pontos.fold(0.0, (total, ponto) => total + ponto.horasExtras);

  static String formatHours(double hours) {
    final minutes = (hours * 60).round();
    return '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';
  }
}
