import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class PontoModel {
  PontoModel({
    this.id,
    required this.employeeId,
    required this.employeeName,
    required this.data,
    this.entrada1,
    this.saida1,
    this.entrada2,
    this.saida2,
    this.horasTrabalhadas = 0,
    this.horasExtras = 0,
    this.observacoes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory PontoModel.fromMap(Map<String, dynamic> map) {
    return PontoModel(
      id: map['id'],
      employeeId: map['employee_id'],
      employeeName: map['employee_name'] ?? '',
      data: DateTime.parse(map['data']),
      entrada1:
          map['entrada1'] != null ? DateTime.parse(map['entrada1']) : null,
      saida1: map['saida1'] != null ? DateTime.parse(map['saida1']) : null,
      entrada2:
          map['entrada2'] != null ? DateTime.parse(map['entrada2']) : null,
      saida2: map['saida2'] != null ? DateTime.parse(map['saida2']) : null,
      horasTrabalhadas: (map['horas_trabalhadas'] ?? 0).toDouble(),
      horasExtras: (map['horas_extras'] ?? 0).toDouble(),
      observacoes: map['observacoes'] ?? '',
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  int? id;
  int employeeId;
  String employeeName;
  DateTime data;
  DateTime? entrada1;
  DateTime? saida1;
  DateTime? entrada2;
  DateTime? saida2;
  double horasTrabalhadas;
  double horasExtras;
  String observacoes;
  DateTime createdAt;
  DateTime updatedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'employee_id': employeeId,
        'employee_name': employeeName,
        'data': data.toIso8601String(),
        'entrada1': entrada1?.toIso8601String(),
        'saida1': saida1?.toIso8601String(),
        'entrada2': entrada2?.toIso8601String(),
        'saida2': saida2?.toIso8601String(),
        'horas_trabalhadas': horasTrabalhadas,
        'horas_extras': horasExtras,
        'observacoes': observacoes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  String get dataFormatada => DateFormat('dd/MM/yyyy').format(data);

  String get entrada1Formatada =>
      entrada1 != null ? DateFormat('HH:mm').format(entrada1!) : '-';

  String get saida1Formatada =>
      saida1 != null ? DateFormat('HH:mm').format(saida1!) : '-';

  String get entrada2Formatada =>
      entrada2 != null ? DateFormat('HH:mm').format(entrada2!) : '-';

  String get saida2Formatada =>
      saida2 != null ? DateFormat('HH:mm').format(saida2!) : '-';

  String get horasTrabalhadasFormatada {
    final horas = horasTrabalhadas.floor();
    final minutos = ((horasTrabalhadas - horas) * 60).round();
    return '${horas.toString().padLeft(2, '0')}:${minutos.toString().padLeft(2, '0')}';
  }

  String get horasExtrasFormatada {
    final horas = horasExtras.floor();
    final minutos = ((horasExtras - horas) * 60).round();
    return '${horas.toString().padLeft(2, '0')}:${minutos.toString().padLeft(2, '0')}';
  }

  Color get statusColor {
    if (entrada1 == null) return Colors.grey;
    if (saida1 == null) return Colors.orange;
    if (entrada2 == null) return Colors.blue;
    if (saida2 == null) return Colors.orange;
    return Colors.green;
  }

  String get statusLabel {
    if (entrada1 == null) return 'Aguardando';
    if (saida1 == null) return 'Em trabalho';
    if (entrada2 == null) return 'Intervalo';
    if (saida2 == null) return 'Em trabalho';
    return 'Finalizado';
  }
}
