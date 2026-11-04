import 'package:intl/intl.dart';

class HoleriteModel {
  HoleriteModel({
    this.id,
    required this.employeeId,
    required this.employeeName,
    required this.mesReferencia,
    this.salarioBase = 0,
    this.horasTrabalhadas = 0,
    this.horasExtras = 0,
    this.valorHora = 0,
    this.valorHoraExtra = 0,
    this.totalHorasExtras = 0,
    this.salarioBruto = 0,
    this.descontos = 0,
    this.valeTransporte = 0,
    this.valeAlimentacao = 0,
    this.insalubridade = 0,
    this.periculosidade = 0,
    this.comissao = 0,
    this.outros = 0,
    this.inss = 0,
    this.irrf = 0,
    this.salarioLiquido = 0,
    this.observacoes = '',
    this.pago = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory HoleriteModel.fromMap(Map<String, dynamic> map) {
    return HoleriteModel(
      id: map['id'],
      employeeId: map['employee_id'],
      employeeName: map['employee_name'] ?? '',
      mesReferencia: map['mes_referencia'] ?? '',
      salarioBase: (map['salario_base'] ?? 0).toDouble(),
      horasTrabalhadas: (map['horas_trabalhadas'] ?? 0).toDouble(),
      horasExtras: (map['horas_extras'] ?? 0).toDouble(),
      valorHora: (map['valor_hora'] ?? 0).toDouble(),
      valorHoraExtra: (map['valor_hora_extra'] ?? 0).toDouble(),
      totalHorasExtras: (map['total_horas_extras'] ?? 0).toDouble(),
      salarioBruto: (map['salario_bruto'] ?? 0).toDouble(),
      descontos: (map['descontos'] ?? 0).toDouble(),
      valeTransporte: (map['vale_transporte'] ?? 0).toDouble(),
      valeAlimentacao: (map['vale_alimentacao'] ?? 0).toDouble(),
      insalubridade: (map['insalubridade'] ?? 0).toDouble(),
      periculosidade: (map['periculosidade'] ?? 0).toDouble(),
      comissao: (map['comissao'] ?? 0).toDouble(),
      outros: (map['outros'] ?? 0).toDouble(),
      inss: (map['inss'] ?? 0).toDouble(),
      irrf: (map['irrf'] ?? 0).toDouble(),
      salarioLiquido: (map['salario_liquido'] ?? 0).toDouble(),
      observacoes: map['observacoes'] ?? '',
      pago: map['pago'] == 1,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  int? id;
  int employeeId;
  String employeeName;
  String mesReferencia;
  double salarioBase;
  double horasTrabalhadas;
  double horasExtras;
  double valorHora;
  double valorHoraExtra;
  double totalHorasExtras;
  double salarioBruto;
  double descontos;
  double valeTransporte;
  double valeAlimentacao;
  double insalubridade;
  double periculosidade;
  double comissao;
  double outros;
  double inss;
  double irrf;
  double salarioLiquido;
  String observacoes;
  bool pago;
  DateTime createdAt;
  DateTime updatedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'employee_id': employeeId,
        'employee_name': employeeName,
        'mes_referencia': mesReferencia,
        'salario_base': salarioBase,
        'horas_trabalhadas': horasTrabalhadas,
        'horas_extras': horasExtras,
        'valor_hora': valorHora,
        'valor_hora_extra': valorHoraExtra,
        'total_horas_extras': totalHorasExtras,
        'salario_bruto': salarioBruto,
        'descontos': descontos,
        'vale_transporte': valeTransporte,
        'vale_alimentacao': valeAlimentacao,
        'insalubridade': insalubridade,
        'periculosidade': periculosidade,
        'comissao': comissao,
        'outros': outros,
        'inss': inss,
        'irrf': irrf,
        'salario_liquido': salarioLiquido,
        'observacoes': observacoes,
        'pago': pago ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  // MÉTODO COPYWITH
  HoleriteModel copyWith({
    int? id,
    int? employeeId,
    String? employeeName,
    String? mesReferencia,
    double? salarioBase,
    double? horasTrabalhadas,
    double? horasExtras,
    double? valorHora,
    double? valorHoraExtra,
    double? totalHorasExtras,
    double? salarioBruto,
    double? descontos,
    double? valeTransporte,
    double? valeAlimentacao,
    double? insalubridade,
    double? periculosidade,
    double? comissao,
    double? outros,
    double? inss,
    double? irrf,
    double? salarioLiquido,
    String? observacoes,
    bool? pago,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HoleriteModel(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      employeeName: employeeName ?? this.employeeName,
      mesReferencia: mesReferencia ?? this.mesReferencia,
      salarioBase: salarioBase ?? this.salarioBase,
      horasTrabalhadas: horasTrabalhadas ?? this.horasTrabalhadas,
      horasExtras: horasExtras ?? this.horasExtras,
      valorHora: valorHora ?? this.valorHora,
      valorHoraExtra: valorHoraExtra ?? this.valorHoraExtra,
      totalHorasExtras: totalHorasExtras ?? this.totalHorasExtras,
      salarioBruto: salarioBruto ?? this.salarioBruto,
      descontos: descontos ?? this.descontos,
      valeTransporte: valeTransporte ?? this.valeTransporte,
      valeAlimentacao: valeAlimentacao ?? this.valeAlimentacao,
      insalubridade: insalubridade ?? this.insalubridade,
      periculosidade: periculosidade ?? this.periculosidade,
      comissao: comissao ?? this.comissao,
      outros: outros ?? this.outros,
      inss: inss ?? this.inss,
      irrf: irrf ?? this.irrf,
      salarioLiquido: salarioLiquido ?? this.salarioLiquido,
      observacoes: observacoes ?? this.observacoes,
      pago: pago ?? this.pago,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get mesReferenciaFormatada {
    try {
      final parts = mesReferencia.split('-');
      final mes = int.parse(parts[1]);
      final ano = int.parse(parts[0]);
      final meses = [
        'Janeiro',
        'Fevereiro',
        'Março',
        'Abril',
        'Maio',
        'Junho',
        'Julho',
        'Agosto',
        'Setembro',
        'Outubro',
        'Novembro',
        'Dezembro'
      ];
      return '${meses[mes - 1]}/$ano';
    } catch (e) {
      return mesReferencia;
    }
  }

  String get salarioBaseFormatado =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(salarioBase);

  String get salarioBrutoFormatado =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
          .format(salarioBruto);

  String get salarioLiquidoFormatado =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
          .format(salarioLiquido);

  String get descontosFormatado =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(descontos);

  String get inssFormatado =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(inss);

  String get irrfFormatado =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(irrf);
}
