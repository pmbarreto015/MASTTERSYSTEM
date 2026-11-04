/// Definições dos cadastros operacionais do departamento pessoal.
/// Valores e documentos são informados pelo RH; esta camada não substitui
/// cálculo trabalhista homologado nem uma integração oficial do eSocial.
enum HrFieldKind {
  text,
  notes,
  date,
  money,
  number,
  employee,
  choice,
  attachment
}

class HrField {
  const HrField(this.key, this.label,
      {this.kind = HrFieldKind.text,
      this.required = false,
      this.options = const []});
  final String key;
  final String label;
  final HrFieldKind kind;
  final bool required;
  final List<String> options;
}

class HrModule {
  const HrModule(this.key, this.title, this.description,
      {this.fields = const [],
      this.statuses = const [
        'Pendente',
        'Em andamento',
        'Concluído',
        'Cancelado'
      ],
      this.financial = false});
  final String key;
  final String title;
  final String description;
  final List<HrField> fields;
  final List<String> statuses;
  final bool financial;

  static const employee = HrField('employee_id', 'Colaborador',
      kind: HrFieldKind.employee, required: true);
  static const notes = HrField('notes', 'Observações', kind: HrFieldKind.notes);
  static const amount = HrField('amount', 'Valor aprovado (R\$)',
      kind: HrFieldKind.money, required: true);
  static const due =
      HrField('due_date', 'Vencimento', kind: HrFieldKind.date, required: true);
  static const attachment = HrField('attachment', 'Documento / comprovante',
      kind: HrFieldKind.attachment);

  static const modules = <HrModule>[
    HrModule('dashboard', 'Dashboard RH',
        'Indicadores, agenda de férias e pendências do departamento.'),
    HrModule('colaboradores', 'Colaboradores',
        'Cadastro, situação, salários, ponto e holerites existentes.'),
    HrModule('cargos', 'Cargos e departamentos',
        'Estrutura de cargos, setores, responsáveis e faixa salarial.',
        fields: [
          HrField('department', 'Departamento', required: true),
          HrField('position', 'Cargo / função', required: true),
          HrField('manager', 'Gestor / cargo superior'),
          HrField('salary', 'Salário de referência (R\$)',
              kind: HrFieldKind.money),
          HrField('activities', 'Atribuições', kind: HrFieldKind.notes),
          notes,
        ],
        statuses: [
          'Ativo',
          'Inativo'
        ]),
    HrModule('recrutamento', 'Recrutamento',
        'Vagas, candidatos, currículos e entrevistas.',
        fields: [
          HrField('vacancy', 'Vaga', required: true),
          HrField('candidate', 'Candidato', required: true),
          HrField('contact', 'E-mail / telefone'),
          HrField('interview_date', 'Data da entrevista',
              kind: HrFieldKind.date),
          HrField('interviewer', 'Entrevistador'),
          HrField('feedback', 'Avaliação da entrevista',
              kind: HrFieldKind.notes),
          attachment,
        ],
        statuses: [
          'Inscrito',
          'Triagem',
          'Entrevista',
          'Aprovado',
          'Reprovado',
          'Contratado'
        ]),
    HrModule('admissao', 'Admissão',
        'Checklist de contratação e documentos admissionais.',
        fields: [
          employee,
          HrField('start_date', 'Início do contrato',
              kind: HrFieldKind.date, required: true),
          HrField('contract', 'Tipo de contrato',
              kind: HrFieldKind.choice,
              options: [
                'CLT',
                'Experiência',
                'Estágio',
                'Aprendiz',
                'Prestador',
                'Outro'
              ]),
          HrField('department', 'Departamento / equipe'),
          HrField('documents_checklist', 'Checklist de documentos e pendências',
              kind: HrFieldKind.notes, required: true),
          HrField('responsible', 'Responsável pela admissão', required: true),
          attachment,
          notes,
        ],
        statuses: [
          'Documentação pendente',
          'Em conferência',
          'Aprovado',
          'Concluído',
          'Cancelado'
        ]),
    HrModule('desempenho', 'Desempenho',
        'Avaliações, metas, produtividade e feedbacks.',
        fields: [
          employee,
          HrField('evaluation_date', 'Data da avaliação',
              kind: HrFieldKind.date, required: true),
          HrField('evaluator', 'Avaliador', required: true),
          HrField('score', 'Nota (0 a 10)', kind: HrFieldKind.number),
          HrField('target', 'Meta e indicador de produtividade',
              kind: HrFieldKind.notes, required: true),
          HrField('result', 'Resultado / feedback', kind: HrFieldKind.notes),
          HrField('next_review', 'Próxima avaliação', kind: HrFieldKind.date),
          notes,
        ]),
    HrModule('treinamentos', 'Treinamentos',
        'Capacitações, participantes, carga horária e certificados.',
        fields: [
          employee,
          HrField('course', 'Curso / capacitação', required: true),
          HrField('provider', 'Instituição / instrutor'),
          HrField('start_date', 'Data do treinamento',
              kind: HrFieldKind.date, required: true),
          HrField('hours', 'Carga horária', kind: HrFieldKind.number),
          HrField('expiry_date', 'Validade do certificado',
              kind: HrFieldKind.date),
          attachment,
          notes,
        ],
        statuses: [
          'Inscrito',
          'Em andamento',
          'Concluído',
          'Não compareceu',
          'Cancelado'
        ]),
    HrModule('ponto', 'Controle de ponto',
        'Registros de entrada e saída, jornada, extras e relatório individual.'),
    HrModule('ferias', 'Férias',
        'Períodos aquisitivos, programação, valores e aprovações.',
        fields: [
          employee,
          HrField('acquisition_start', 'Início do período aquisitivo',
              kind: HrFieldKind.date, required: true),
          HrField('acquisition_end', 'Fim do período aquisitivo',
              kind: HrFieldKind.date, required: true),
          HrField('start_date', 'Início das férias',
              kind: HrFieldKind.date, required: true),
          HrField('end_date', 'Fim das férias',
              kind: HrFieldKind.date, required: true),
          HrField('approver', 'Responsável pela aprovação'),
          amount,
          due,
          notes,
        ],
        statuses: [
          'Solicitado',
          'Em análise',
          'Aprovado',
          'Em férias',
          'Concluído',
          'Recusado'
        ],
        financial: true),
    HrModule('folha', 'Folha de pagamento',
        'Folhas conferidas, salários, descontos, encargos e integração financeira.',
        fields: [
          employee,
          HrField('competence', 'Competência (AAAA-MM)', required: true),
          HrField('gross', 'Remuneração bruta conferida (R\$)',
              kind: HrFieldKind.money, required: true),
          HrField('deductions', 'Descontos conferidos (R\$)',
              kind: HrFieldKind.money),
          HrField('charges', 'Encargos conferidos (R\$)',
              kind: HrFieldKind.money),
          amount,
          due,
          attachment,
          notes,
        ],
        statuses: [
          'Rascunho',
          'Em conferência',
          'Aprovado',
          'Enviado ao financeiro',
          'Cancelado'
        ],
        financial: true),
    HrModule('beneficios', 'Benefícios',
        'Transporte, alimentação, convênios, adicionais e adiantamentos.',
        fields: [
          employee,
          HrField('benefit', 'Benefício',
              kind: HrFieldKind.choice,
              required: true,
              options: [
                'Vale-transporte',
                'Alimentação',
                'Convênio médico',
                'Adicional',
                'Adiantamento',
                'Outro'
              ]),
          HrField('competence', 'Competência (AAAA-MM)', required: true),
          amount,
          due,
          HrField('employee_share', 'Participação do colaborador (R\$)',
              kind: HrFieldKind.money),
          notes,
        ],
        statuses: [
          'Solicitado',
          'Aprovado',
          'Enviado ao financeiro',
          'Cancelado'
        ],
        financial: true),
    HrModule('afastamentos', 'Atestados e afastamentos',
        'Licenças, faltas justificadas, períodos e documentos.',
        fields: [
          employee,
          HrField('reason', 'Motivo / tipo',
              kind: HrFieldKind.choice,
              required: true,
              options: [
                'Atestado médico',
                'Licença maternidade',
                'Licença paternidade',
                'Licença remunerada',
                'Falta justificada',
                'Falta não justificada',
                'Outro'
              ]),
          HrField('start_date', 'Início',
              kind: HrFieldKind.date, required: true),
          HrField('end_date', 'Fim', kind: HrFieldKind.date, required: true),
          HrField('responsible', 'Conferido por'),
          attachment,
          notes,
        ],
        statuses: [
          'Recebido',
          'Em análise',
          'Aprovado',
          'Concluído',
          'Recusado'
        ]),
    HrModule('rescisoes', 'Rescisões',
        'Desligamentos, aviso, verbas conferidas e documentação.',
        fields: [
          employee,
          HrField('termination_date', 'Data do desligamento',
              kind: HrFieldKind.date, required: true),
          HrField('reason', 'Motivo',
              kind: HrFieldKind.choice,
              required: true,
              options: [
                'Pedido de demissão',
                'Sem justa causa',
                'Com justa causa',
                'Acordo',
                'Fim de contrato',
                'Outro'
              ]),
          HrField('notice', 'Aviso prévio', kind: HrFieldKind.choice, options: [
            'Trabalhado',
            'Indenizado',
            'Dispensado',
            'Não se aplica'
          ]),
          HrField(
              'calculation', 'Memória de cálculo conferida pelo responsável',
              kind: HrFieldKind.notes, required: true),
          amount,
          due,
          attachment,
          notes,
        ],
        statuses: [
          'Em preparação',
          'Em conferência',
          'Aprovado',
          'Enviado ao financeiro',
          'Concluído',
          'Cancelado'
        ],
        financial: true),
    HrModule('sst', 'Saúde e segurança',
        'Exames, ASO, entrega de EPI e acompanhamento de SST.',
        fields: [
          employee,
          HrField('event', 'Tipo de registro',
              kind: HrFieldKind.choice,
              required: true,
              options: [
                'ASO admissional',
                'ASO periódico',
                'ASO demissional',
                'Retorno ao trabalho',
                'Entrega de EPI',
                'Treinamento SST',
                'Ocorrência'
              ]),
          HrField('event_date', 'Data', kind: HrFieldKind.date, required: true),
          HrField('expiry_date', 'Próximo exame / validade',
              kind: HrFieldKind.date),
          HrField('provider', 'Clínica / profissional responsável',
              required: true),
          HrField('details', 'Equipamento, CA, quantidade ou resultado',
              kind: HrFieldKind.notes),
          attachment,
          notes,
        ],
        statuses: [
          'Agendado',
          'Pendente',
          'Concluído',
          'Vencido',
          'Cancelado'
        ]),
    HrModule('documentos', 'Documentos digitais',
        'Arquivos, contratos e acompanhamento de assinaturas externas.',
        fields: [
          employee,
          HrField('document_type', 'Tipo de documento', required: true),
          HrField('document_date', 'Data do documento',
              kind: HrFieldKind.date, required: true),
          attachment,
          HrField('signature_provider', 'Provedor externo de assinatura'),
          HrField('signature_protocol', 'Protocolo / comprovante do provedor'),
          HrField('signature_url', 'Endereço de verificação do provedor'),
          notes,
        ],
        statuses: [
          'Recebido',
          'Em conferência',
          'Aguardando assinatura externa',
          'Assinatura comprovada pelo provedor',
          'Arquivado'
        ]),
    HrModule('portal', 'Portal do colaborador',
        'Consulta individual pelo RH e acompanhamento de solicitações.',
        fields: [
          employee,
          HrField('request_type', 'Solicitação',
              kind: HrFieldKind.choice,
              required: true,
              options: [
                'Férias',
                'Correção de ponto',
                'Holerite',
                'Benefício',
                'Documento',
                'Atualização cadastral',
                'Outro'
              ]),
          HrField('request_date', 'Data da solicitação',
              kind: HrFieldKind.date, required: true),
          HrField('request', 'Detalhes da solicitação',
              kind: HrFieldKind.notes, required: true),
          HrField('response', 'Resposta do RH', kind: HrFieldKind.notes),
          attachment,
        ],
        statuses: [
          'Aberto',
          'Em análise',
          'Atendido',
          'Recusado'
        ]),
    HrModule('relatorios', 'Relatórios RH',
        'Custos, faltas, admissões, desligamentos e distribuição por cargo.'),
    HrModule('configuracoes', 'Configurações e integrações',
        'Regras internas, auditoria e preparação de eventos eSocial.',
        fields: [
          HrField('configuration_type', 'Tipo',
              kind: HrFieldKind.choice,
              required: true,
              options: [
                'Jornada e banco de horas',
                'Regra interna',
                'Integração eSocial',
                'Integração com ponto',
                'Equipe de produção',
                'Evento eSocial em preparação'
              ]),
          HrField('responsible', 'Responsável', required: true),
          HrField('provider', 'Provedor oficial / sistema externo'),
          HrField('endpoint', 'Endereço da integração (sem senhas)'),
          HrField('event_type', 'Tipo de evento eSocial (se aplicável)'),
          HrField('rules', 'Regras / dados do evento para revisão',
              kind: HrFieldKind.notes, required: true),
          notes,
        ],
        statuses: [
          'Rascunho',
          'Em revisão',
          'Configurado internamente',
          'Aguardando integração externa',
          'Inativo'
        ]),
  ];

  static HrModule byKey(String key) => modules.firstWhere((m) => m.key == key);

  /// Valida também importações e edições fora do formulário.
  Map<String, String> validate(Map<String, dynamic> payload) {
    final errors = <String, String>{};
    for (final field in fields) {
      final value = payload[field.key];
      if (field.required &&
          (value == null || value.toString().trim().isEmpty)) {
        errors[field.key] = 'Informe ${field.label.toLowerCase()}.';
        continue;
      }
      if (value == null || value.toString().isEmpty) continue;
      if ((field.kind == HrFieldKind.money ||
              field.kind == HrFieldKind.number) &&
          (value is! num || !value.isFinite || value < 0)) {
        errors[field.key] = 'Informe um valor válido, maior ou igual a zero.';
      }
      if (field.kind == HrFieldKind.date &&
          (DateTime.tryParse(value.toString()) == null ||
              value.toString().length < 10 ||
              DateTime.tryParse(value.toString())
                      ?.toIso8601String()
                      .substring(0, 10) !=
                  value.toString().substring(0, 10))) {
        errors[field.key] = 'Informe uma data válida.';
      }
      if (field.kind == HrFieldKind.employee && (value is! int || value <= 0)) {
        errors[field.key] = 'Selecione um colaborador válido.';
      }
      if (field.kind == HrFieldKind.choice && !field.options.contains(value)) {
        errors[field.key] = 'Selecione uma opção válida.';
      }
    }
    final start = DateTime.tryParse('${payload['start_date']}');
    final end = DateTime.tryParse('${payload['end_date']}');
    if (start != null && end != null && end.isBefore(start)) {
      errors['end_date'] =
          'A data final deve ser igual ou posterior à inicial.';
    }
    final acquisitionStart =
        DateTime.tryParse('${payload['acquisition_start']}');
    final acquisitionEnd = DateTime.tryParse('${payload['acquisition_end']}');
    if (acquisitionStart != null &&
        acquisitionEnd != null &&
        acquisitionEnd.isBefore(acquisitionStart)) {
      errors['acquisition_end'] = 'O período aquisitivo é inválido.';
    }
    if (payload['competence'] != null &&
        !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$')
            .hasMatch('${payload['competence']}')) {
      errors['competence'] = 'Use AAAA-MM, por exemplo 2026-10.';
    }
    final score = payload['score'];
    if (score is num && score > 10)
      errors['score'] = 'A nota deve estar entre 0 e 10.';
    if (key == 'folha' &&
        payload['gross'] is num &&
        payload['deductions'] is num &&
        (payload['deductions'] as num) > (payload['gross'] as num)) {
      errors['deductions'] =
          'Os descontos não podem superar a remuneração bruta.';
    }
    if (key == 'documentos' &&
        payload['signature_protocol'] != null &&
        payload['signature_protocol'].toString().trim().isNotEmpty &&
        '${payload['signature_provider'] ?? ''}'.trim().isEmpty) {
      errors['signature_provider'] = 'Informe o provedor do comprovante.';
    }
    return errors;
  }
}
