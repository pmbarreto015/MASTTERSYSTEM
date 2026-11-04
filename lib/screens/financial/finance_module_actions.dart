part of 'financial_modules_screen.dart';

extension _FinanceActions on _FinancialModulesScreenState {
  int? _id(dynamic value) => int.tryParse(value?.toString() ?? '');

  Future<void> _editTransaction(
      {String? type, FinancialModel? transaction}) async {
    final meta = _meta(transaction?.id);
    final categoryOptions = {
      ..._categories,
      if (transaction != null) transaction.categoria: transaction.categoriaLabel
    };
    final data = await _form(
        transaction == null ? 'Novo lançamento' : 'Editar lançamento', [
      const FinanceField('title', 'Descrição', required: true),
      const FinanceField('type', 'Tipo',
          kind: 'select',
          required: true,
          options: {'receber': 'Conta a receber', 'pagar': 'Conta a pagar'}),
      const FinanceField('amount', 'Valor líquido (R\$)',
          kind: 'money', required: true, minimum: .01),
      const FinanceField('dueDate', 'Vencimento', kind: 'date', required: true),
      const FinanceField('customer', 'Cliente ou fornecedor'),
      FinanceField('category', 'Categoria',
          kind: 'select', required: true, options: categoryOptions),
      const FinanceField('method', 'Forma de pagamento',
          kind: 'select',
          options: {
            'PIX': 'PIX',
            'Dinheiro': 'Dinheiro',
            'Débito': 'Débito',
            'Crédito': 'Crédito',
            'Boleto': 'Boleto',
            'Transferência': 'Transferência',
            'Outro': 'Outro',
          }),
      FinanceField('accountId', 'Conta bancária / caixa',
          kind: 'select', options: _options('account')),
      FinanceField('centerId', 'Centro de custos',
          kind: 'select', options: _options('cost_center')),
      FinanceField('orderId', 'Pedido vinculado', kind: 'select', options: {
        for (final o in _orders.where((o) => o.isAcceptedSale))
          '${o.id}': '${o.numero} — ${o.clienteNome ?? ''}',
      }),
      const FinanceField('paid', 'Valor já pago', kind: 'bool'),
      const FinanceField('notes', 'Documento / observações', kind: 'multiline'),
    ],
        initial: {
          'title': transaction?.description,
          'type': transaction?.type ?? type ?? 'receber',
          'amount': transaction?.amount,
          'dueDate': transaction?.dueDate.toIso8601String(),
          'customer': transaction?.customerName,
          'category': transaction?.categoria ??
              (type == 'pagar' ? 'operacional' : 'vendas'),
          'method': transaction?.formaPagamento ?? 'PIX',
          'accountId': meta?.payload['accountId'],
          'centerId': meta?.payload['centerId'],
          'orderId': transaction?.orderId,
          'paid': transaction?.isPaid ?? false,
          'notes': transaction?.notes,
        });
    if (data == null || !mounted) return;
    await _run(() async {
      final now = DateTime.now();
      final orderId = _id(data['orderId']);
      final order = _orders.where((o) => o.id == orderId).firstOrNull;
      await _service.saveTransaction(
          FinancialModel(
            id: transaction?.id,
            description: data['title'] as String,
            amount: _number(data['amount']),
            type: data['type'] as String,
            dueDate: DateTime.parse(data['dueDate'] as String),
            customerName: data['customer'] as String,
            categoria: data['category'] as String,
            formaPagamento: data['method'] as String? ?? '',
            isPaid: data['paid'] == true,
            status: data['paid'] == true
                ? 'pago'
                : (transaction?.status == 'parcial' ? 'parcial' : 'pendente'),
            notes: data['notes'] as String,
            orderId: orderId,
            customerId: order?.clienteId ?? transaction?.customerId,
            parcela: transaction?.parcela ?? 0,
            totalParcelas: transaction?.totalParcelas ?? 0,
            valorBruto: transaction?.valorBruto ?? 0,
            taxa: transaction?.taxa ?? 0,
            valorLiquido: _number(data['amount']),
            pagamentos: transaction?.pagamentos ?? [],
            createdAt: transaction?.createdAt ?? now,
            updatedAt: now,
          ),
          accountId: _id(data['accountId']),
          centerId: _id(data['centerId']));
    }, success: 'Lançamento salvo.');
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) =>
              AlertDialog(title: Text(title), content: Text(message), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Voltar')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Confirmar'))
              ])) ??
      false;

  Future<void> _settle(FinancialModel transaction) async {
    if (!await _confirm('Registrar baixa integral',
            '${transaction.description}\n${_money.format(transaction.amount)}\nConfirmar o recebimento ou pagamento deste valor?') ||
        !mounted) return;
    await _run(() => _service.settle(transaction),
        success: 'Baixa registrada.');
  }

  Future<void> _cancel(FinancialModel transaction) async {
    if (!await _confirm('Cancelar lançamento',
            '${transaction.description}\nO lançamento será preservado como cancelado e deixará de compor os totais. ${transaction.isPaid ? 'O valor já pago também sairá dos saldos.' : ''}') ||
        !mounted) return;
    await _run(() => _service.cancel(transaction),
        success: 'Lançamento cancelado.');
  }

  Future<void> _partial(FinancialModel transaction) async {
    final data = await _form(
        'Pagamento parcial',
        [
          FinanceField('amount', 'Valor recebido (R\$)',
              kind: 'money',
              required: true,
              minimum: .01,
              maximum: transaction.amount),
          const FinanceField('date', 'Data do recebimento',
              kind: 'date', required: true),
        ],
        description:
            '${transaction.description}\nSaldo em aberto: ${_money.format(transaction.amount)}');
    if (data == null || !mounted) return;
    await _run(() async {
      final before = (await _service.financial.getAll(includeCancelled: true))
          .map((t) => t.id)
          .toSet();
      await _service.financial.registrarPagamentoParcial(transaction.id!,
          _number(data['amount']), DateTime.parse(data['date'] as String));
      final meta = _meta(transaction.id);
      final after = await _service.financial.getAll();
      // A baixa parcial cria um novo recebimento; herda a classificação da origem.
      for (final row in after.where((r) =>
          !before.contains(r.id) &&
          r.isPaid &&
          r.orderId == transaction.orderId &&
          r.customerId == transaction.customerId &&
          r.description.endsWith(transaction.description))) {
        await _service.saveTransaction(row,
            accountId: meta?.payload['accountId'] as int?,
            centerId: meta?.payload['centerId'] as int?);
      }
      await _service.audit('Recebimento parcial', 'financial',
          targetId: transaction.id,
          details: _money.format(_number(data['amount'])));
    }, success: 'Pagamento parcial registrado.');
  }

  Future<void> _editRecord(String type, {ErpModuleRecord? record}) async {
    final title = switch (type) {
      'account' => 'Conta bancária ou caixa',
      'recurrence' => 'Despesa recorrente',
      'category' => 'Categoria financeira',
      'card_plan' => 'Plano de cartão',
      'collection' => 'Contato ou acordo de cobrança',
      'commission_rule' => 'Regra de comissão',
      'cost_center' => 'Centro de custos',
      _ => 'Cadastro',
    };
    final fields = <FinanceField>[
      const FinanceField('title', 'Descrição / nome', required: true)
    ];
    switch (type) {
      case 'account':
        fields.addAll([
          const FinanceField('kind', 'Tipo',
              kind: 'select',
              required: true,
              options: {
                'banco': 'Conta bancária',
                'caixa': 'Caixa',
                'carteira': 'Carteira digital'
              }),
          const FinanceField('bank', 'Banco / instituição'),
          const FinanceField('branch', 'Agência'),
          const FinanceField('number', 'Número da conta'),
          const FinanceField('openingBalance', 'Saldo inicial (R\$)',
              kind: 'money', required: true),
          const FinanceField('openingDate', 'Data do saldo inicial',
              kind: 'date', required: true),
        ]);
      case 'recurrence':
        fields.addAll([
          const FinanceField('supplier', 'Fornecedor'),
          const FinanceField('amount', 'Valor mensal (R\$)',
              kind: 'money', required: true, minimum: .01),
          const FinanceField('nextDate', 'Primeira / próxima competência',
              kind: 'date', required: true),
          FinanceField('category', 'Categoria',
              kind: 'select', required: true, options: _categories),
          FinanceField('centerId', 'Centro de custos',
              kind: 'select', options: _options('cost_center')),
        ]);
      case 'category':
        fields.addAll([
          const FinanceField('kind', 'Classificação',
              kind: 'select',
              required: true,
              options: {
                'receita': 'Receita',
                'fixa': 'Despesa fixa',
                'variavel': 'Despesa variável',
                'custo': 'Custo direto'
              }),
          const FinanceField('notes', 'Regra de uso', kind: 'multiline'),
        ]);
      case 'card_plan':
        fields.addAll([
          const FinanceField('customer', 'Cliente'),
          const FinanceField('gross', 'Valor bruto (R\$)',
              kind: 'money', required: true, minimum: .01),
          const FinanceField('fee', 'Taxa da operadora (%)',
              kind: 'number', required: true, minimum: 0, maximum: 99.99),
          const FinanceField('advanceFee', 'Taxa total de antecipação (%)',
              kind: 'number', required: true, minimum: 0, maximum: 99.99),
          const FinanceField('count', 'Quantidade de parcelas',
              kind: 'integer', required: true, minimum: 1, maximum: 120),
          const FinanceField('firstDate', 'Primeiro vencimento',
              kind: 'date', required: true),
        ]);
      case 'collection':
        fields.addAll([
          FinanceField('financialId', 'Conta a receber',
              kind: 'select',
              required: true,
              options: {
                for (final t in _rows.where((t) =>
                    t.type == 'receber' &&
                    !t.isPaid &&
                    t.status != 'cancelado'))
                  '${t.id}': '${t.description} — ${_money.format(t.amount)}',
              }),
          const FinanceField('channel', 'Canal',
              kind: 'select',
              required: true,
              options: {
                'whatsapp': 'WhatsApp',
                'telefone': 'Telefone',
                'email': 'E-mail',
                'presencial': 'Presencial'
              }),
          const FinanceField('phone', 'WhatsApp com DDD'),
          const FinanceField(
              'agreementAmount', 'Valor proposto / combinado (R\$)',
              kind: 'money', required: true, minimum: 0),
          const FinanceField('interest', 'Juros propostos (%)',
              kind: 'number', minimum: 0, maximum: 100),
          const FinanceField('fine', 'Multa proposta (%)',
              kind: 'number', minimum: 0, maximum: 100),
          const FinanceField('nextDate', 'Próxima ação / vencimento do acordo',
              kind: 'date'),
          const FinanceField(
              'notes', 'Resultado do contato / condições do acordo',
              kind: 'multiline', required: true),
        ]);
      case 'commission_rule':
        fields.addAll([
          const FinanceField('seller', 'Vendedor / beneficiário',
              required: true),
          const FinanceField('percentage', 'Percentual (%)',
              kind: 'number', required: true, minimum: .01, maximum: 100),
          const FinanceField('basis', 'Base de cálculo',
              kind: 'select',
              required: true,
              options: {
                'sale': 'Valor da venda',
                'received': 'Valores já recebidos'
              }),
          FinanceField('centerId', 'Centro de custos',
              kind: 'select', options: _options('cost_center')),
        ]);
      case 'cost_center':
        fields.addAll([
          const FinanceField('unit', 'Unidade / setor', required: true),
          const FinanceField('responsible', 'Responsável'),
          const FinanceField('notes', 'Atividade / observações',
              kind: 'multiline'),
        ]);
    }
    final config = _type('config').firstOrNull;
    final data = await _form(
        record == null ? 'Novo — $title' : 'Editar — $title', fields,
        initial: {
          'openingBalance': 0,
          'fee': 0,
          'advanceFee': 0,
          'count': 1,
          'category': 'operacional',
          'basis': 'sale',
          'interest': config?.payload['interest'] ?? 0,
          'fine': config?.payload['fine'] ?? 0,
          ...?record?.payload,
          'title': record?.title
        },
        description: type == 'card_plan'
            ? 'Não gere um plano para recebíveis que já existem no financeiro. A antecipação usa a taxa total informada; não consulta a operadora.'
            : null);
    if (data == null || !mounted) return;
    await _run(() async {
      if (type == 'card_plan' &&
          _number(data['fee']) + _number(data['advanceFee']) >= 100) {
        throw ArgumentError('A soma das taxas deve ser menor que 100%.');
      }
      if (type == 'category' &&
          _type('category').any((r) =>
              r.id != record?.id &&
              r.title.toLowerCase() ==
                  (data['title'] as String).toLowerCase())) {
        throw ArgumentError('Já existe uma categoria com esse nome.');
      }
      final payload = {...data}..remove('title');
      for (final key in ['centerId', 'financialId']) {
        if (payload.containsKey(key)) payload[key] = _id(payload[key]);
      }
      if (type == 'recurrence')
        payload['day'] = DateTime.parse(data['nextDate'] as String).day;
      if (type == 'collection') {
        payload['actor'] = _service.actor;
        payload['actorId'] = _service.actorId;
      }
      await _service.saveRecord(ErpModuleRecord(
        id: record?.id,
        module: FinanceWorkspaceService.module,
        recordType: type,
        title: data['title'] as String,
        status: record?.status ?? (type == 'card_plan' ? 'rascunho' : 'ativo'),
        payload: payload,
        referenceId: record?.referenceId,
        createdAt: record?.createdAt,
      ));
    }, success: 'Cadastro salvo.');
  }

  Future<void> _archiveRecord(ErpModuleRecord record) async {
    if (!await _confirm('Desativar cadastro',
            'Desativar ${record.title}? O histórico será preservado.') ||
        !mounted) return;
    await _run(() async {
      if (record.recordType == 'account') {
        final latest = await _service.load();
        final financial = await _service.financial.getAll();
        if (FinanceWorkspaceService.accountBalance(
                    record.id!, latest, financial)
                .abs() >=
            .005) {
          throw StateError('Transfira o saldo antes de desativar a conta.');
        }
        final assigned = latest
            .where((r) =>
                r.recordType == 'transaction_meta' &&
                r.payload['accountId'] == record.id)
            .map((r) => r.payload['financialId'])
            .toSet();
        if (financial.any((r) => !r.isPaid && assigned.contains(r.id)))
          throw StateError('Existem lançamentos pendentes nesta conta.');
      }
      await _service.archive(record);
    }, success: 'Cadastro desativado.');
  }

  Future<void> _transfer() async {
    if (_options('account').length < 2) {
      _message('Cadastre pelo menos duas contas ativas.', error: true);
      return;
    }
    final data = await _form('Transferência entre contas', [
      FinanceField('fromId', 'Origem',
          kind: 'select', required: true, options: _options('account')),
      FinanceField('toId', 'Destino',
          kind: 'select', required: true, options: _options('account')),
      const FinanceField('amount', 'Valor (R\$)',
          kind: 'money', required: true, minimum: .01),
      const FinanceField('date', 'Data', kind: 'date', required: true),
      const FinanceField('title', 'Descrição'),
    ]);
    if (data == null || !mounted) return;
    final ref = const Uuid().v4();
    await _run(
        () => _service.transfer(
            fromId: _id(data['fromId'])!,
            toId: _id(data['toId'])!,
            amount: _number(data['amount']),
            date: DateTime.parse(data['date'] as String),
            description: data['title'] as String,
            reference: ref),
        success: 'Transferência registrada.');
  }

  Future<void> _importOfx() async {
    if (_options('account').isEmpty) {
      _message('Cadastre uma conta antes de importar.', error: true);
      return;
    }
    final data = await _form(
        'Conta para conciliação',
        [
          FinanceField('accountId', 'Conta bancária',
              kind: 'select', required: true, options: _options('account'))
        ],
        description:
            'O arquivo será importado apenas para conferência. Nenhum pagamento será registrado automaticamente.');
    if (data == null || !mounted) return;
    final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['ofx'], withData: true);
    if (selected == null || !mounted) return;
    await _run(() async {
      final file = selected.files.single;
      if (file.size > 20 * 1024 * 1024)
        throw ArgumentError('O OFX deve ter até 20 MB.');
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      String source;
      try {
        source = utf8.decode(bytes);
      } on FormatException {
        source = latin1.decode(bytes);
      }
      final count = await _service.importOfx(source, _id(data['accountId'])!);
      if (mounted)
        _message(
            '$count movimentos novos importados. Duplicados foram ignorados.');
    });
  }

  Future<void> _reconcile(ErpModuleRecord entry) async {
    final amount = _number(entry.payload['amount']);
    final used = _type('ofx')
        .where((r) => r.status == 'conciliado')
        .map((r) => r.payload['financialId'])
        .toSet();
    final eligible = _rows
        .where((t) =>
            t.status != 'cancelado' &&
            !used.contains(t.id) &&
            (t.type == 'receber') == (amount > 0) &&
            (t.amount * 100).round() == (amount.abs() * 100).round())
        .toList();
    if (eligible.isEmpty) {
      _message(
          'Não há lançamento com valor e natureza correspondentes. Cadastre ou corrija a conta a receber/pagar primeiro.',
          error: true);
      return;
    }
    final data = await _form(
        'Conferir movimento OFX',
        [
          FinanceField('id', 'Lançamento correspondente',
              kind: 'select',
              required: true,
              options: {
                for (final t in eligible)
                  '${t.id}':
                      '${_date.format(t.dueDate)} — ${t.description} (${t.statusLabel})'
              })
        ],
        description:
            '${entry.title}\n${_money.format(amount)} • ${_recordName(entry.payload['accountId'] as int?)}\nAo confirmar, o lançamento será marcado como pago nesta conta.');
    if (data == null || !mounted) return;
    await _run(
        () => _service.reconcile(
            entry, eligible.firstWhere((t) => t.id == _id(data['id']))),
        success: 'Movimento conciliado.');
  }

  Future<void> _generateRecurring(ErpModuleRecord record) async {
    final data = await _form(
        'Gerar despesas recorrentes',
        [
          const FinanceField('until', 'Gerar competências até',
              kind: 'date', required: true)
        ],
        initial: {'until': (_range?.end ?? DateTime.now()).toIso8601String()},
        description:
            '${record.title}\nAs contas serão criadas em aberto, uma por mês.');
    if (data == null || !mounted) return;
    await _run(() async {
      final count = await _service.generateRecurring(
          record, DateTime.parse(data['until'] as String));
      if (mounted) _message('$count competências processadas.');
    });
  }

  Future<void> _generateCard(ErpModuleRecord plan) async {
    if (!await _confirm('Gerar recebíveis',
            '${plan.title}\nCriar ${plan.payload['count']} parcelas no financeiro? Confirme que esta venda ainda não foi lançada.') ||
        !mounted) return;
    await _run(() async {
      await _service.generateCardPlan(plan);
    }, success: 'Recebíveis de cartão gerados.');
  }

  Future<void> _collectionMessage(ErpModuleRecord record) async {
    var phone =
        '${record.payload['phone'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
    if (phone.length == 10 || phone.length == 11) phone = '55$phone';
    if (phone.length < 12 || phone.length > 15) {
      _message('Informe um WhatsApp com DDD no contato de cobrança.',
          error: true);
      return;
    }
    final transaction =
        _rows.where((t) => t.id == record.payload['financialId']).firstOrNull;
    final message =
        'Olá! Gostaríamos de conversar sobre ${transaction?.description ?? record.title}. '
        'Valor combinado: ${_money.format(_number(record.payload['agreementAmount']))}. ${record.payload['notes'] ?? ''}';
    await _run(() async {
      final opened = await launchUrl(
          Uri.https('wa.me', '/$phone', {'text': message}),
          mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('Não foi possível abrir o WhatsApp.');
      await _service.audit('Abertura de mensagem WhatsApp', 'collection',
          targetId: record.id, details: record.title);
    });
  }

  Future<void> _generateCommission(ErpModuleRecord rule) async {
    final options = {
      for (final o in _orders.where((o) => o.isAcceptedSale))
        '${o.id}': '${o.numero} — ${o.clienteNome ?? ''}'
    };
    final data = await _form(
        'Apurar comissão',
        [
          FinanceField('orderId', 'Pedido',
              kind: 'select', required: true, options: options),
          const FinanceField('dueDate', 'Vencimento da comissão',
              kind: 'date', required: true)
        ],
        description:
            '${rule.payload['seller']} • ${rule.payload['percentage']}%\nA apuração usa a base existente agora. Cada regra/pedido é apurada uma única vez.');
    if (data == null || !mounted) return;
    await _run(() async {
      final order = (await OrderRepository().getAll())
          .firstWhere((o) => o.id == _id(data['orderId']) && o.isAcceptedSale);
      final all = await _service.load();
      final reference = 'commission:${rule.id}:${order.id}';
      if (all.any((r) =>
          r.recordType == 'commission_accrual' && r.referenceId == reference))
        throw StateError('Esta regra já foi apurada para o pedido.');
      final financial = await _service.financial.getByOrderId(order.id!);
      final basis = rule.payload['basis'] == 'received'
          ? financial
              .where((t) =>
                  t.type == 'receber' && t.isPaid && t.status != 'cancelado')
              .fold<double>(0, (v, t) => v + t.amount)
          : order.valorTotal;
      final amount =
          (basis * _number(rule.payload['percentage'])).round() / 100;
      if (amount <= 0)
        throw StateError('Não há base positiva para apurar comissão.');
      final now = DateTime.now();
      final saved = await _service.generateTransaction(
          reference: reference,
          transaction: FinancialModel(
              description:
                  'Comissão — ${rule.payload['seller']} — Pedido ${order.numero}',
              amount: amount,
              type: 'pagar',
              dueDate: DateTime.parse(data['dueDate'] as String),
              customerName: '${rule.payload['seller']}',
              orderId: order.id,
              categoria: 'pessoal',
              createdAt: now,
              updatedAt: now),
          centerId: rule.payload['centerId'] as int?);
      await _service.saveRecord(ErpModuleRecord(
        module: FinanceWorkspaceService.module,
        recordType: 'commission_accrual',
        referenceId: reference,
        title: '${rule.title} — ${rule.payload['seller']}',
        payload: {
          'ruleId': rule.id,
          'orderId': order.id,
          'orderNumber': order.numero,
          'basisAmount': basis,
          'amount': amount,
          'financialId': saved.id,
          'percentage': rule.payload['percentage']
        },
      ));
    }, success: 'Comissão registrada em contas a pagar.');
  }

  Future<void> _configure() async {
    final config = _type('config').firstOrNull;
    final data = await _form('Regras financeiras', [
      const FinanceField('interest', 'Juros sugeridos (%)',
          kind: 'number', required: true, minimum: 0, maximum: 100),
      const FinanceField('fine', 'Multa sugerida (%)',
          kind: 'number', required: true, minimum: 0, maximum: 100),
      const FinanceField('notes', 'Política de cobrança / regras internas',
          kind: 'multiline'),
    ], initial: {
      'interest': 0,
      'fine': 0,
      ...?config?.payload
    });
    if (data == null || !mounted) return;
    await _run(() async {
      if (!context.read<AuthProvider>().isAdmin)
        throw StateError('Somente administradores podem alterar as regras.');
      await _service.saveRecord(ErpModuleRecord(
          id: config?.id,
          module: FinanceWorkspaceService.module,
          recordType: 'config',
          referenceId: 'default',
          title: 'Regras financeiras',
          payload: data,
          createdAt: config?.createdAt));
    }, success: 'Regras financeiras salvas.');
  }

  Future<void> _closeCash() async {
    if (_range == null) {
      _message('Selecione um período para o fechamento.', error: true);
      return;
    }
    final totals = FinancePeriodTotals(_periodRows);
    final data = await _form(
        'Registrar fechamento de caixa',
        [
          const FinanceField('counted', 'Saldo conferido (R\$)',
              kind: 'money', required: true),
          const FinanceField(
              'notes', 'Observações / justificativa da diferença',
              kind: 'multiline'),
        ],
        initial: {'counted': totals.balance},
        description:
            '$_periodLabel\nSaldo realizado pelos filtros atuais: ${_money.format(totals.balance)}. '
            'O fechamento registra uma fotografia da conferência; não bloqueia lançamentos futuros ou altera saldos.');
    if (data == null || !mounted) return;
    await _run(() async {
      if (!context.read<AuthProvider>().isAdmin)
        throw StateError('Somente administradores podem fechar caixa.');
      await _service.saveRecord(ErpModuleRecord(
          module: FinanceWorkspaceService.module,
          recordType: 'cash_close',
          title: _periodLabel,
          payload: {
            'from': _range!.start.toIso8601String(),
            'to': _range!.end.toIso8601String(),
            'received': totals.received,
            'paid': totals.paid,
            'balance': totals.balance,
            'counted': data['counted'],
            'difference': _number(data['counted']) - totals.balance,
            'notes': data['notes'],
            'actor': _service.actor,
            'actorId': _service.actorId,
            'filter': {'search': _search.text, 'status': _status},
          }));
    }, success: 'Conferência de caixa registrada.');
  }

  (List<String>, List<List<String>>) _currentReport() {
    final kind = _selected == 13
        ? _reportType
        : switch (_selected) {
            3 => 'fluxo',
            7 => 'dre',
            11 => 'centros',
            12 => 'pedidos',
            _ => 'lancamentos'
          };
    if (kind == 'fluxo')
      return (
        [
          'Dia',
          'Entradas',
          'Saídas',
          'A receber',
          'A pagar',
          'Realizado acumulado',
          'Previsto acumulado'
        ],
        _flowRows()
      );
    if (kind == 'dre') return (['Indicador', 'Valor'], _dreRows());
    if (kind == 'centros')
      return (
        ['Centro', 'Unidade', 'Receitas', 'Despesas', 'Resultado', 'Status'],
        _centerRows()
      );
    if (kind == 'pedidos')
      return (
        [
          'Pedido',
          'Cliente',
          'Venda',
          'Recebido',
          'Saldo devedor',
          'Custo itens',
          'Despesas vinculadas',
          'Margem estimada'
        ],
        _orderRows()
      );
    final rows = _periodRows.where((t) =>
        (_selected != 1 || t.type == 'receber') &&
        (_selected != 2 || t.type == 'pagar'));
    return (
      [
        'ID',
        'Vencimento',
        'Descrição',
        'Cliente / fornecedor',
        'Tipo',
        'Categoria',
        'Valor',
        'Status',
        'Conta',
        'Centro'
      ],
      rows
          .map((t) => [
                '${t.id}',
                _date.format(t.dueDate),
                t.description,
                t.customerName ?? '',
                t.tipoLabel,
                _categories[t.categoria] ?? t.categoria,
                _money.format(t.amount),
                t.statusLabel,
                _recordName(_meta(t.id)?.payload['accountId'] as int?),
                _recordName(_meta(t.id)?.payload['centerId'] as int?)
              ])
          .toList()
    );
  }

  Future<void> _export(String format) async {
    await _run(() async {
      final report = _currentReport();
      final title = _selected == 13 ? _reportType : _modules[_selected].title;
      Uint8List bytes;
      if (format == 'pdf') {
        bytes = await FinanceReportService.pdf(
            title: title,
            period: _periodLabel,
            columns: report.$1,
            rows: report.$2);
        await Printing.layoutPdf(
            onLayout: (_) async => bytes, name: 'financeiro.pdf');
      } else {
        bytes = format == 'csv'
            ? FinanceReportService.csvBytes(report.$1, report.$2)
            : FinanceReportService.excel(report.$1, report.$2);
        final path = await FilePicker.platform.saveFile(
            dialogTitle: 'Salvar relatório financeiro',
            fileName:
                'financeiro_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.$format',
            type: FileType.custom,
            allowedExtensions: [format],
            bytes: bytes);
        if (path != null && !Platform.isAndroid && !Platform.isIOS)
          await File(path).writeAsBytes(bytes, flush: true);
        if (path != null && mounted) _message('Relatório salvo.');
      }
    });
  }
}
