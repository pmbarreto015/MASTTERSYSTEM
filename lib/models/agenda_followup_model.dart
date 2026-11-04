class AgendaFollowupModel {
  AgendaFollowupModel({
    this.id,
    required this.clienteNome,
    this.telefone = '',
    required this.assunto,
    this.observacoes = '',
    this.status = 'responder',
    this.periodicidade = 'unico',
    required this.agendadoPara,
    this.concluidoEm,
    DateTime? criadoEm,
    DateTime? atualizadoEm,
  })  : criadoEm = criadoEm ?? DateTime.now(),
        atualizadoEm = atualizadoEm ?? DateTime.now();

  factory AgendaFollowupModel.fromMap(Map<String, dynamic> map) =>
      AgendaFollowupModel(
        id: map['id'] as int?,
        clienteNome: map['cliente_nome'] as String? ?? '',
        telefone: map['telefone'] as String? ?? '',
        assunto: map['assunto'] as String? ?? '',
        observacoes: map['observacoes'] as String? ?? '',
        status: map['status'] as String? ?? 'responder',
        periodicidade: map['periodicidade'] as String? ?? 'unico',
        agendadoPara: DateTime.parse(map['agendado_para'] as String),
        concluidoEm: map['concluido_em'] == null
            ? null
            : DateTime.tryParse(map['concluido_em'] as String),
        criadoEm: DateTime.parse(map['created_at'] as String),
        atualizadoEm: DateTime.parse(map['updated_at'] as String),
      );

  final int? id;
  final String clienteNome;
  final String telefone;
  final String assunto;
  final String observacoes;
  final String status;
  final String periodicidade;
  final DateTime agendadoPara;
  final DateTime? concluidoEm;
  final DateTime criadoEm;
  final DateTime atualizadoEm;

  bool get concluido => status == 'concluido';

  Map<String, dynamic> toMap() => {
        'id': id,
        'cliente_nome': clienteNome,
        'telefone': telefone,
        'assunto': assunto,
        'observacoes': observacoes,
        'status': status,
        'periodicidade': periodicidade,
        'agendado_para': agendadoPara.toIso8601String(),
        'concluido_em': concluidoEm?.toIso8601String(),
        'created_at': criadoEm.toIso8601String(),
        'updated_at': atualizadoEm.toIso8601String(),
      };

  AgendaFollowupModel copyWith({
    int? id,
    String? clienteNome,
    String? telefone,
    String? assunto,
    String? observacoes,
    String? status,
    String? periodicidade,
    DateTime? agendadoPara,
    DateTime? concluidoEm,
    bool limparConclusao = false,
    DateTime? criadoEm,
    DateTime? atualizadoEm,
  }) =>
      AgendaFollowupModel(
        id: id ?? this.id,
        clienteNome: clienteNome ?? this.clienteNome,
        telefone: telefone ?? this.telefone,
        assunto: assunto ?? this.assunto,
        observacoes: observacoes ?? this.observacoes,
        status: status ?? this.status,
        periodicidade: periodicidade ?? this.periodicidade,
        agendadoPara: agendadoPara ?? this.agendadoPara,
        concluidoEm: limparConclusao ? null : (concluidoEm ?? this.concluidoEm),
        criadoEm: criadoEm ?? this.criadoEm,
        atualizadoEm: atualizadoEm ?? DateTime.now(),
      );
}
