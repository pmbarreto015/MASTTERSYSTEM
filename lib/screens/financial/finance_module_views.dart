part of 'financial_modules_screen.dart';

extension _FinanceViews on _FinancialModulesScreenState {
  Widget _moduleBody() => switch (_selected) {
        0 => _dashboard(),
        1 => _transactionsModule('receber'),
        2 => _transactionsModule('pagar'),
        3 => _cashFlow(),
        4 => _accounts(),
        5 => _ofx(),
        6 => _expenses(),
        7 => _dre(),
        8 => _cards(),
        9 => _collections(),
        10 => _commissions(),
        11 => _centers(),
        12 => _byOrder(),
        13 => _reports(),
        _ => _settings(),
      };

  Widget _dashboard() {
    final totals = FinancePeriodTotals(_periodRows);
    final today = DateTime.now();
    final todaySales = _salesFor(_dayRange(today));
    final monthSales = _salesFor(_monthRange(today));
    final yearSales = _salesFor(_yearRange(today));
    final selectedSales = _range == null
        ? _salesRows.fold<double>(0, (total, t) => total + t.amount)
        : _salesFor(_range!);
    // O valor em aberto n?o pode depender do filtro de m?s: uma parcela com
    // vencimento futuro ainda precisa aparecer no atalho de recebimento.
    final openReceivables = _rows
        .where(
            (t) => t.type == 'receber' && !t.isPaid && t.status != 'cancelado')
        .toList();
    final openReceivableTotal = openReceivables.fold<double>(
        0, (total, transaction) => total + transaction.amount);
    final overdue = _periodRows.where((t) => t.isOverdue).toList();
    final receiving = overdue
        .where((t) => t.type == 'receber')
        .fold<double>(0, (a, t) => a + t.amount);
    final paying = overdue
        .where((t) => t.type == 'pagar')
        .fold<double>(0, (a, t) => a + t.amount);
    final months = <String, (double, double)>{};
    for (final t in _periodRows) {
      final key = DateFormat('yyyy-MM').format(t.dueDate);
      final old = months[key] ?? (0.0, 0.0);
      months[key] = t.type == 'receber'
          ? (old.$1 + t.amount, old.$2)
          : (old.$1, old.$2 + t.amount);
    }
    final keys = months.keys.toList()..sort();
    final maximum = months.values.fold<double>(
        1, (max, v) => [max, v.$1, v.$2].reduce((a, b) => a > b ? a : b));
    return _section('Dashboard financeiro',
        description:
            'Vendas são apuradas pela data de criação das contas a receber. Os demais indicadores seguem o vencimento; baixas parciais já entram no saldo realizado.',
        actions: [
          _button('Novo lançamento', Icons.add, () => _editTransaction())
        ],
        children: [
          Text('Vendas', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _metric('Vendido hoje', todaySales, Icons.today, Colors.teal),
            _metric('Vendido no mês', monthSales, Icons.calendar_month,
                Colors.blue),
            _metric('Vendido no ano', yearSales, Icons.calendar_today,
                Colors.indigo),
            _metric('Vendido no período', selectedSales, Icons.date_range,
                Colors.deepPurple),
          ]),
          const SizedBox(height: 20),
          Text('Caixa e compromissos',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _metric('Recebido', totals.received, Icons.south_west, Colors.teal),
            _metric(
                'Despesas pagas', totals.paid, Icons.north_east, Colors.red),
            _metric('Saldo realizado', totals.balance,
                Icons.account_balance_wallet, Colors.blue),
            _receivableShortcut(openReceivableTotal, openReceivables.length),
            _metric(
                'A pagar', totals.payable, Icons.event_busy, Colors.deepOrange),
            _metric('Saldo previsto', totals.projected, Icons.timeline,
                Colors.indigo),
          ]),
          const SizedBox(height: 14),
          Card(
              child: ListTile(
                  leading: Icon(
                      overdue.isEmpty
                          ? Icons.check_circle
                          : Icons.warning_amber,
                      color: overdue.isEmpty ? Colors.teal : Colors.orange),
                  title: Text('${overdue.length} lançamentos vencidos'),
                  subtitle: Text(
                      'A receber: ${_money.format(receiving)}  •  A pagar: ${_money.format(paying)}'),
                  trailing: TextButton(
                      onPressed: () => _updateFinanceView(() {
                            _status = 'vencido';
                            _selected = 1;
                          }),
                      child: const Text('Consultar')))),
          const SizedBox(height: 14),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Receitas e despesas por mês',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        const Text(
                            'Receitas em verde • despesas em vermelho • valores pagos e em aberto'),
                        if (keys.isEmpty)
                          const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text(
                                  'Cadastre um lançamento para acompanhar a evolução.')),
                        for (final key in keys)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                        '${key.substring(5)}/${key.substring(0, 4)} — ${_money.format(months[key]!.$1)} / ${_money.format(months[key]!.$2)}'),
                                    const SizedBox(height: 5),
                                    LinearProgressIndicator(
                                        value: (months[key]!.$1 / maximum)
                                            .clamp(0, 1),
                                        color: Colors.teal,
                                        backgroundColor:
                                            Colors.teal.withValues(alpha: .08),
                                        minHeight: 9),
                                    const SizedBox(height: 3),
                                    LinearProgressIndicator(
                                        value: (months[key]!.$2 / maximum)
                                            .clamp(0, 1),
                                        color: Colors.red.shade300,
                                        backgroundColor:
                                            Colors.red.withValues(alpha: .08),
                                        minHeight: 9),
                                  ])),
                      ]))),
        ]);
  }

  Widget _receivableShortcut(double total, int count) => SizedBox(
        width: 198,
        child: Card(
          color: Colors.orange.withValues(alpha: .13),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _updateFinanceView(() {
              _range = null;
              _status = 'pendente';
              _selected = 1;
            }),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.payments_outlined,
                          color: Colors.orange.shade800),
                      const SizedBox(width: 8),
                      const Text('A receber',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 10),
                    Text(_money.format(total),
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900)),
                    const SizedBox(height: 3),
                    Text(
                        '$count ${count == 1 ? 'conta em aberto' : 'contas em aberto'}\nToque para receber',
                        style: const TextStyle(fontSize: 11)),
                  ]),
            ),
          ),
        ),
      );

  Widget _transactionTable(List<FinancialModel> rows, {bool actions = true}) =>
      FinanceTable(
          columns: [
            'Descrição / cliente',
            'Vencimento',
            'Valor',
            'Status',
            'Conta / centro',
            if (actions) 'Ações'
          ],
          rows: rows.map((t) {
            final meta = _meta(t.id);
            return DataRow(cells: [
              _cell('${t.description}\n${t.customerName ?? ''}'),
              _cell(_date.format(t.dueDate)),
              _cell(_money.format(t.amount)),
              DataCell(_tag(t.statusLabel, t.statusColor)),
              _cell(
                  '${_recordName(meta?.payload['accountId'] as int?)}\n${_recordName(meta?.payload['centerId'] as int?, 'Sem centro de custos')}'),
              if (actions)
                _actions([
                  _icon('Editar lançamento', Icons.edit_outlined,
                      () => _editTransaction(transaction: t)),
                  if (!t.isPaid)
                    _icon('Registrar baixa integral',
                        Icons.check_circle_outline, () => _settle(t)),
                  if (!t.isPaid && t.type == 'receber')
                    _icon('Pagamento parcial', Icons.payments_outlined,
                        () => _partial(t)),
                  _icon('Cancelar lançamento', Icons.cancel_outlined,
                      () => _cancel(t)),
                ]),
            ]);
          }).toList());

  Widget _transactionsModule(String type) {
    final rows = _periodRows.where((r) => r.type == type).toList();
    final totals = FinancePeriodTotals(rows);
    return _section(type == 'receber' ? 'Contas a receber' : 'Contas a pagar',
        description:
            'Parcelas, vencimentos, vínculo bancário, centro de custos e baixas. Os lançamentos dos pedidos continuam integrados.',
        actions: [
          _button(
              'Novo lançamento', Icons.add, () => _editTransaction(type: type)),
          OutlinedButton.icon(
              onPressed: () => _export('pdf'),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('PDF'))
        ],
        children: [
          Wrap(spacing: 10, runSpacing: 10, children: [
            _metric(
                'Em aberto',
                type == 'receber' ? totals.receivable : totals.payable,
                Icons.pending_actions,
                Colors.orange.shade800),
            _metric(
                type == 'receber' ? 'Recebido' : 'Pago',
                type == 'receber' ? totals.received : totals.paid,
                Icons.task_alt,
                Colors.teal),
          ]),
          const SizedBox(height: 12),
          _transactionTable(rows)
        ]);
  }

  List<List<String>> _flowRows() {
    final days = <String, List<FinancialModel>>{};
    for (final t in _periodRows) {
      days
          .putIfAbsent(DateFormat('yyyy-MM-dd').format(t.dueDate), () => [])
          .add(t);
    }
    final keys = days.keys.toList()..sort();
    var balance = 0.0, projected = 0.0;
    return keys.map((key) {
      final totals = FinancePeriodTotals(days[key]!);
      balance += totals.balance;
      projected += totals.projected;
      return [
        _displayDate(key),
        _money.format(totals.received),
        _money.format(totals.paid),
        _money.format(totals.receivable),
        _money.format(totals.payable),
        _money.format(balance),
        _money.format(projected)
      ];
    }).toList();
  }

  Widget _cashFlow() => _section('Fluxo de caixa',
          description:
              'Variação diária e acumulada no período, agrupada pelo vencimento. O previsto soma realizado e pendências; saldos bancários estão em Bancos e Contas.',
          actions: [
            OutlinedButton.icon(
                onPressed: () => _export('xlsx'),
                icon: const Icon(Icons.download),
                label: const Text('Excel'))
          ],
          children: [
            FinanceTable(
                columns: const [
                  'Dia',
                  'Entradas',
                  'Saídas',
                  'A receber',
                  'A pagar',
                  'Realizado acumulado',
                  'Previsto acumulado'
                ],
                rows: _flowRows()
                    .map((r) => DataRow(cells: r.map(_cell).toList()))
                    .toList())
          ]);

  Widget _accounts() => _section('Bancos e contas',
          description:
              'Saldo inicial + lançamentos pagos vinculados + transferências. Lançamentos sem conta ficam separados e não compõem saldos bancários.',
          actions: [
            _button('Nova conta', Icons.add, () => _editRecord('account')),
            OutlinedButton.icon(
                onPressed: _busy ? null : _transfer,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Transferir'))
          ],
          children: [
            FinanceTable(
                columns: const [
                  'Conta',
                  'Tipo / banco',
                  'Saldo inicial',
                  'Saldo atual',
                  'Status',
                  'Ações'
                ],
                rows: _searchType('account')
                    .map((r) => DataRow(cells: [
                          _cell(r.title),
                          _cell(
                              '${r.payload['kind'] ?? ''}\n${r.payload['bank'] ?? ''}'),
                          _cell(_money
                              .format(_number(r.payload['openingBalance']))),
                          _cell(_money.format(
                              FinanceWorkspaceService.accountBalance(
                                  r.id!, _records, _rows))),
                          DataCell(_tag(r.status,
                              r.status == 'ativo' ? Colors.teal : Colors.grey)),
                          _actions([
                            _icon('Editar conta', Icons.edit_outlined,
                                () => _editRecord('account', record: r)),
                            if (r.status == 'ativo')
                              _icon('Arquivar conta', Icons.archive_outlined,
                                  () => _archiveRecord(r)),
                          ])
                        ]))
                    .toList()),
            const SizedBox(height: 18),
            Text('Transferências no período',
                style: Theme.of(context).textTheme.titleMedium),
            FinanceTable(
                columns: const [
                  'Data',
                  'Descrição',
                  'Origem',
                  'Destino',
                  'Valor'
                ],
                rows: _searchType('transfer')
                    .where((r) =>
                        _inPeriod(DateTime.parse(r.payload['date'] as String)))
                    .map((r) => DataRow(cells: [
                          _cell(_displayDate(r.payload['date'])),
                          _cell(r.title),
                          _cell(_recordName(r.payload['fromId'] as int?)),
                          _cell(_recordName(r.payload['toId'] as int?)),
                          _cell(_money.format(_number(r.payload['amount']))),
                        ]))
                    .toList()),
          ]);

  Widget _ofx() => _section('Conciliação bancária',
          description:
              'A importação não altera o financeiro. Confira valor, natureza e conta antes de associar; a confirmação registra a baixa integral.',
          actions: [
            _button('Importar OFX', Icons.upload_file, _importOfx)
          ],
          children: [
            FinanceTable(
                columns: const [
                  'Data',
                  'Movimento',
                  'Conta',
                  'Valor',
                  'Status / vínculo',
                  'Conferir'
                ],
                rows: _searchType('ofx')
                    .where((r) =>
                        _inPeriod(DateTime.parse(r.payload['date'] as String)))
                    .map((r) => DataRow(cells: [
                          _cell(_displayDate(r.payload['date'])),
                          _cell('${r.title}\nFITID ${r.payload['externalId']}'),
                          _cell(_recordName(r.payload['accountId'] as int?)),
                          _cell(_money.format(_number(r.payload['amount']))),
                          _cell(
                              '${r.status}${r.payload['financialId'] == null ? '' : ' • lançamento #${r.payload['financialId']}'}'),
                          _actions([
                            if (r.status != 'conciliado')
                              _icon('Associar e registrar baixa', Icons.link,
                                  () => _reconcile(r))
                            else
                              const Icon(Icons.verified, color: Colors.teal)
                          ]),
                        ]))
                    .toList()),
          ]);

  Widget _expenses() {
    final expenses = _periodRows.where((r) => r.type == 'pagar').toList();
    final byCategory = <String, double>{};
    for (final r in expenses) {
      byCategory.update(r.categoria, (v) => v + r.amount,
          ifAbsent: () => r.amount);
    }
    return _section('Controle de despesas',
        description:
            'Recorrências mensais geram contas a pagar por competência. Consulte os lançamentos para registrar os pagamentos.',
        actions: [
          _button(
              'Nova despesa', Icons.add, () => _editTransaction(type: 'pagar')),
          OutlinedButton.icon(
              onPressed: () => _editRecord('recurrence'),
              icon: const Icon(Icons.repeat),
              label: const Text('Nova recorrência'))
        ],
        children: [
          Wrap(
              spacing: 10,
              runSpacing: 10,
              children: byCategory.entries
                  .map((entry) => _metric(_categories[entry.key] ?? entry.key,
                      entry.value, Icons.category, Colors.deepOrange))
                  .toList()),
          const SizedBox(height: 18),
          Text('Despesas recorrentes',
              style: Theme.of(context).textTheme.titleMedium),
          FinanceTable(
              columns: const [
                'Descrição / fornecedor',
                'Valor',
                'Próxima competência',
                'Categoria',
                'Status',
                'Ações'
              ],
              rows: _searchType('recurrence')
                  .map((r) => DataRow(cells: [
                        _cell('${r.title}\n${r.payload['supplier'] ?? ''}'),
                        _cell(_money.format(_number(r.payload['amount']))),
                        _cell(_displayDate(r.payload['nextDate'])),
                        _cell('${r.payload['category']}'),
                        _cell(r.status),
                        _actions([
                          _icon('Editar recorrência', Icons.edit_outlined,
                              () => _editRecord('recurrence', record: r)),
                          if (r.status == 'ativo')
                            _icon(
                                'Gerar competências',
                                Icons.play_circle_outline,
                                () => _generateRecurring(r)),
                          if (r.status == 'ativo')
                            _icon('Desativar', Icons.archive_outlined,
                                () => _archiveRecord(r))
                        ]),
                      ]))
                  .toList()),
          const SizedBox(height: 18),
          _transactionTable(expenses),
        ]);
  }

  List<List<String>> _dreRows() {
    final totals = FinancePeriodTotals(_periodRows);
    final directCategories = {
      'materiais',
      'terceirizacao',
      ..._type('category')
          .where((r) => r.payload['kind'] == 'custo')
          .map((r) => r.title)
    };
    final costs = _periodRows
        .where(
            (r) => r.type == 'pagar' && directCategories.contains(r.categoria))
        .fold<double>(0, (v, r) => v + r.amount);
    return [
      ['Receitas lançadas', _money.format(totals.revenue)],
      ['Custos diretos lançados', _money.format(costs)],
      ['Resultado bruto gerencial', _money.format(totals.revenue - costs)],
      ['Demais despesas lançadas', _money.format(totals.expense - costs)],
      ['Resultado gerencial', _money.format(totals.result)],
      ['Margem sobre receitas', '${totals.margin.toStringAsFixed(2)}%'],
      ['Resultado realizado (pagos)', _money.format(totals.balance)],
    ];
  }

  Widget _dre() => _section('DRE e lucratividade',
          description:
              'Demonstrativo gerencial pelo vencimento das contas. Custos diretos: materiais, terceirização e categorias classificadas como custo. Custos estimados da produção aparecem no módulo por pedido e não são somados novamente aqui.',
          actions: [
            OutlinedButton.icon(
                onPressed: () => _export('pdf'),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Exportar DRE'))
          ],
          children: [
            FinanceTable(
                columns: const ['Indicador', 'Valor'],
                rows: _dreRows()
                    .map((r) => DataRow(cells: r.map(_cell).toList()))
                    .toList()),
            const SizedBox(height: 14),
            FinanceTable(
                columns: const ['Categoria', 'Receitas menos despesas'],
                rows: FinancePeriodTotals(_periodRows)
                    .categories
                    .entries
                    .map((e) => DataRow(cells: [
                          _cell(_categories[e.key] ?? e.key),
                          _cell(_money.format(e.value))
                        ]))
                    .toList())
          ]);

  Widget _cards() => _section('Cartões e parcelamentos',
          description:
              'Planos geram recebíveis líquidos com taxa da operadora e taxa de antecipação informadas. Crie planos apenas para vendas ainda não lançadas no financeiro.',
          actions: [
            _button('Novo plano de recebimento', Icons.add,
                () => _editRecord('card_plan'))
          ],
          children: [
            FinanceTable(
                columns: const [
                  'Plano / cliente',
                  'Bruto',
                  'Taxas',
                  'Parcelas',
                  'Primeiro vencimento',
                  'Status',
                  'Ações'
                ],
                rows: _searchType('card_plan')
                    .map((r) => DataRow(cells: [
                          _cell('${r.title}\n${r.payload['customer'] ?? ''}'),
                          _cell(_money.format(_number(r.payload['gross']))),
                          _cell(
                              '${_number(r.payload['fee']) + _number(r.payload['advanceFee'])}%'),
                          _cell('${r.payload['count']}'),
                          _cell(_displayDate(r.payload['firstDate'])),
                          _cell(r.status),
                          _actions([
                            if (r.status != 'gerado') ...[
                              _icon('Editar plano', Icons.edit_outlined,
                                  () => _editRecord('card_plan', record: r)),
                              _icon(
                                  'Gerar parcelas no financeiro',
                                  Icons.play_circle_outline,
                                  () => _generateCard(r)),
                            ] else
                              const Icon(Icons.check_circle, color: Colors.teal)
                          ]),
                        ]))
                    .toList()),
            const SizedBox(height: 18),
            Text('Recebíveis de cartão no período',
                style: Theme.of(context).textTheme.titleMedium),
            _transactionTable(_periodRows
                .where((r) =>
                    r.type == 'receber' &&
                    (r.taxa > 0 ||
                        r.formaPagamento.toLowerCase().contains('crédito') ||
                        r.formaPagamento.toLowerCase().contains('credito')))
                .toList()),
          ]);

  Widget _collections() {
    final overdue =
        _periodRows.where((r) => r.type == 'receber' && r.isOverdue).toList();
    return _section('Cobranças e inadimplência',
        description:
            'Registre cada contato, acordo e próxima ação. Juros e multa são propostas informadas; não alteram o principal automaticamente.',
        actions: [
          _button('Registrar contato ou acordo', Icons.add,
              () => _editRecord('collection'))
        ],
        children: [
          _metric(
              'Recebíveis vencidos',
              overdue.fold<double>(0, (v, r) => v + r.amount),
              Icons.warning_amber,
              Colors.orange.shade800),
          const SizedBox(height: 16),
          _transactionTable(overdue),
          const SizedBox(height: 20),
          Text('Histórico de contatos e acordos',
              style: Theme.of(context).textTheme.titleMedium),
          FinanceTable(
              columns: const [
                'Data',
                'Contato / acordo',
                'Lançamento',
                'Valor combinado',
                'Próxima ação',
                'Ações'
              ],
              rows: _searchType('collection')
                  .where((r) => _inPeriod(r.createdAt))
                  .map((r) => DataRow(cells: [
                        _cell(_date.format(r.createdAt)),
                        _cell('${r.title}\n${r.payload['notes'] ?? ''}'),
                        _cell(
                            '#${r.payload['financialId']} • ${r.payload['channel'] ?? ''}'),
                        _cell(_money
                            .format(_number(r.payload['agreementAmount']))),
                        _cell(_displayDate(r.payload['nextDate'])),
                        _actions([
                          _icon('Abrir mensagem no WhatsApp',
                              Icons.chat_outlined, () => _collectionMessage(r))
                        ]),
                      ]))
                  .toList()),
        ]);
  }

  Widget _commissions() => _section('Comissões',
          description:
              'Apure por pedido e vendedor, usando o valor da venda ou os recebimentos já pagos. Cada regra e pedido gera uma única comissão a pagar.',
          actions: [
            _button(
                'Nova regra', Icons.add, () => _editRecord('commission_rule'))
          ],
          children: [
            FinanceTable(
                columns: const [
                  'Regra / vendedor',
                  'Percentual',
                  'Base',
                  'Status',
                  'Ações'
                ],
                rows: _searchType('commission_rule')
                    .map((r) => DataRow(cells: [
                          _cell('${r.title}\n${r.payload['seller'] ?? ''}'),
                          _cell('${r.payload['percentage']}%'),
                          _cell(r.payload['basis'] == 'received'
                              ? 'Recebido'
                              : 'Valor da venda'),
                          _cell(r.status),
                          _actions([
                            _icon(
                                'Editar regra',
                                Icons.edit_outlined,
                                () =>
                                    _editRecord('commission_rule', record: r)),
                            if (r.status == 'ativo')
                              _icon('Apurar pedido', Icons.calculate_outlined,
                                  () => _generateCommission(r)),
                            if (r.status == 'ativo')
                              _icon('Desativar regra', Icons.archive_outlined,
                                  () => _archiveRecord(r))
                          ]),
                        ]))
                    .toList()),
            const SizedBox(height: 18),
            Text('Apurações', style: Theme.of(context).textTheme.titleMedium),
            FinanceTable(
                columns: const [
                  'Data',
                  'Comissão',
                  'Pedido',
                  'Base apurada',
                  'Valor',
                  'Conta a pagar'
                ],
                rows: _searchType('commission_accrual')
                    .where((r) => _inPeriod(r.createdAt))
                    .map((r) => DataRow(cells: [
                          _cell(_date.format(r.createdAt)),
                          _cell(r.title),
                          _cell('${r.payload['orderNumber']}'),
                          _cell(
                              _money.format(_number(r.payload['basisAmount']))),
                          _cell(_money.format(_number(r.payload['amount']))),
                          _cell('#${r.payload['financialId']}'),
                        ]))
                    .toList()),
            const SizedBox(height: 16),
            _transactionTable(_periodRows
                .where((r) =>
                    r.type == 'pagar' &&
                    (r.notes ?? '').contains('[finance:commission:'))
                .toList()),
          ]);

  List<List<String>> _centerRows() => _searchType('cost_center').map((center) {
        final ids = _type('transaction_meta')
            .where((r) => r.payload['centerId'] == center.id)
            .map((r) => r.payload['financialId'])
            .toSet();
        final totals =
            FinancePeriodTotals(_periodRows.where((r) => ids.contains(r.id)));
        return [
          center.title,
          '${center.payload['unit'] ?? ''}',
          _money.format(totals.revenue),
          _money.format(totals.expense),
          _money.format(totals.result),
          center.status
        ];
      }).toList();

  Widget _centers() => _section('Centro de custos',
          description:
              'Vincule o centro ao editar cada lançamento. O resultado considera receitas e despesas com vínculo explícito.',
          actions: [
            _button('Novo centro de custos', Icons.add,
                () => _editRecord('cost_center'))
          ],
          children: [
            FinanceTable(
                columns: const [
                  'Centro',
                  'Unidade',
                  'Receitas',
                  'Despesas',
                  'Resultado',
                  'Status'
                ],
                rows: _centerRows()
                    .map((r) => DataRow(cells: r.map(_cell).toList()))
                    .toList()),
            const SizedBox(height: 14),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _searchType('cost_center')
                    .map((r) => OutlinedButton.icon(
                        onPressed: () => _editRecord('cost_center', record: r),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(r.title)))
                    .toList()),
            const SizedBox(height: 18),
            Text(
                'Lançamentos sem centro: ${_periodRows.where((r) => _meta(r.id)?.payload['centerId'] == null).length}'),
            _transactionTable(_periodRows
                .where((r) => _meta(r.id)?.payload['centerId'] == null)
                .toList()),
          ]);

  List<List<String>> _orderRows() => _orders
          .where((o) =>
              o.isAcceptedSale &&
              _inPeriod(DateTime.parse(o.dataCriacao)) &&
              _matches('${o.numero} ${o.clienteNome ?? ''}'))
          .map((order) {
        final rows = _rows
            .where((t) => t.orderId == order.id && t.status != 'cancelado')
            .toList();
        final received = rows
            .where((t) => t.type == 'receber' && t.isPaid)
            .fold<double>(0, (v, t) => v + t.amount);
        final pending = rows
            .where((t) => t.type == 'receber' && !t.isPaid)
            .fold<double>(0, (v, t) => v + t.amount);
        final cost =
            order.itens.fold<double>(0, (v, item) => v + item.custoTotal);
        final linked = rows
            .where((t) => t.type == 'pagar')
            .fold<double>(0, (v, t) => v + t.amount);
        final margin = order.valorTotal > 0
            ? 100 * (order.valorTotal - cost) / order.valorTotal
            : 0;
        return [
          order.numero,
          order.clienteNome ?? '',
          _money.format(order.valorTotal),
          _money.format(received),
          _money.format(pending),
          _money.format(cost),
          _money.format(linked),
          '${margin.toStringAsFixed(2)}%'
        ];
      }).toList();

  Widget _byOrder() => _section('Financeiro por pedido',
          description:
              'Pedidos filtrados pela criação. Pagamentos mostram todo o histórico de cada pedido. Margem estimada = venda menos custos dos itens; despesas vinculadas são exibidas separadamente para evitar dupla contagem.',
          actions: [
            OutlinedButton.icon(
                onPressed: () => _export('xlsx'),
                icon: const Icon(Icons.download),
                label: const Text('Excel'))
          ],
          children: [
            FinanceTable(
                columns: const [
                  'Pedido',
                  'Cliente',
                  'Venda',
                  'Recebido',
                  'Saldo devedor',
                  'Custo dos itens',
                  'Despesas vinculadas',
                  'Margem estimada'
                ],
                rows: _orderRows()
                    .map((r) => DataRow(cells: r.map(_cell).toList()))
                    .toList()),
          ]);

  Widget _reports() {
    final report = _currentReport();
    return _section('Relatórios financeiros',
        description:
            'Os arquivos respeitam a busca, o período e o status dos lançamentos. CSV e Excel contêm todos os registros, inclusive os que estão em outras páginas da tabela.',
        actions: [
          for (final format in ['pdf', 'csv', 'xlsx'])
            OutlinedButton.icon(
                onPressed: _busy ? null : () => _export(format),
                icon: Icon(
                    format == 'pdf' ? Icons.picture_as_pdf : Icons.download),
                label: Text(format == 'xlsx' ? 'Excel' : format.toUpperCase()))
        ],
        children: [
          SizedBox(
              width: 350,
              child: DropdownButtonFormField<String>(
                  initialValue: _reportType,
                  decoration: const InputDecoration(
                      labelText: 'Relatório', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                        value: 'lancamentos',
                        child: Text('Lançamentos financeiros')),
                    DropdownMenuItem(
                        value: 'fluxo', child: Text('Fluxo de caixa')),
                    DropdownMenuItem(
                        value: 'dre', child: Text('DRE gerencial')),
                    DropdownMenuItem(
                        value: 'centros', child: Text('Centros de custos')),
                    DropdownMenuItem(
                        value: 'pedidos', child: Text('Financeiro por pedido'))
                  ],
                  onChanged: (value) => _updateFinanceView(
                      () => _reportType = value ?? 'lancamentos'))),
          const SizedBox(height: 14),
          Text('${report.$2.length} registros • $_periodLabel'),
          const SizedBox(height: 8),
          FinanceTable(
              columns: report.$1,
              rows: report.$2
                  .map((r) => DataRow(cells: r.map(_cell).toList()))
                  .toList()),
        ]);
  }

  Widget _settings() {
    final admin = context.watch<AuthProvider>().isAdmin;
    final config = _type('config').firstOrNull;
    return _section('Configurações e auditoria',
        description:
            'As permissões de acesso são administradas em Usuários. As ações realizadas nestes módulos registram operador, data e objeto alterado.',
        actions: [
          if (admin) _button('Regras financeiras', Icons.settings, _configure),
          if (admin)
            OutlinedButton.icon(
                onPressed: _busy ? null : _closeCash,
                icon: const Icon(Icons.lock_clock),
                label: const Text('Registrar fechamento'))
        ],
        children: [
          Card(
              child: ListTile(
                  leading: const Icon(Icons.rule),
                  title: const Text('Regras de cobrança'),
                  subtitle: Text(
                      'Juros sugeridos: ${_number(config?.payload['interest'])}% • Multa sugerida: ${_number(config?.payload['fine'])}%\n${config?.payload['notes'] ?? ''}'))),
          const SizedBox(height: 14),
          Wrap(alignment: WrapAlignment.spaceBetween, children: [
            Text('Categorias', style: Theme.of(context).textTheme.titleMedium),
            if (admin)
              OutlinedButton.icon(
                  onPressed: () => _editRecord('category'),
                  icon: const Icon(Icons.add),
                  label: const Text('Nova categoria'))
          ]),
          FinanceTable(
              columns: const ['Categoria', 'Classificação', 'Status', 'Ações'],
              rows: _searchType('category')
                  .map((r) => DataRow(cells: [
                        _cell(r.title),
                        _cell('${r.payload['kind']}'),
                        _cell(r.status),
                        _actions([
                          if (admin)
                            _icon('Editar categoria', Icons.edit_outlined,
                                () => _editRecord('category', record: r))
                        ]),
                      ]))
                  .toList()),
          const SizedBox(height: 18),
          Text('Fechamentos de caixa',
              style: Theme.of(context).textTheme.titleMedium),
          FinanceTable(
              columns: const [
                'Data de registro',
                'Período',
                'Recebido',
                'Pago',
                'Saldo',
                'Responsável'
              ],
              rows: _searchType('cash_close')
                  .map((r) => DataRow(cells: [
                        _cell(_date.format(r.createdAt)),
                        _cell(r.title),
                        _cell(_money.format(_number(r.payload['received']))),
                        _cell(_money.format(_number(r.payload['paid']))),
                        _cell(_money.format(_number(r.payload['balance']))),
                        _cell('${r.payload['actor'] ?? ''}'),
                      ]))
                  .toList()),
          const SizedBox(height: 18),
          Text('Auditoria', style: Theme.of(context).textTheme.titleMedium),
          FinanceTable(
              columns: const ['Data / hora', 'Operador', 'Ação', 'Registro'],
              rows: _searchType('audit')
                  .where((r) => _inPeriod(r.createdAt))
                  .map((r) => DataRow(cells: [
                        _cell(
                            DateFormat('dd/MM/yyyy HH:mm').format(r.createdAt)),
                        _cell('${r.payload['actor'] ?? 'Sistema'}'),
                        _cell(r.title),
                        _cell(
                            '${r.payload['targetType'] ?? ''} #${r.payload['targetId'] ?? ''}'),
                      ]))
                  .toList()),
        ]);
  }
}
