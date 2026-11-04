import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../supabase/supabase_config.dart';
import '../supabase/supabase_service.dart';
import 'remote_database.dart';
import 'supabase_database.dart';
import 'erp_modules_schema.dart';

class AppDatabase {
  static const String databaseModeKey = 'database_mode';
  static const String databasePathKey = 'database_shared_path';
  static const String localMode = 'local';
  static const String sharedMode = 'shared';
  static const String remoteMode = 'remote';
  static const String supabaseMode = 'supabase';
  static const String databaseServerUrlKey = 'database_server_url';
  static const String databaseServerTokenKey = 'database_server_token';
  static const String supabaseProjectUrlKey = 'supabase_project_url';
  static const String supabasePublishableKeyKey = 'supabase_publishable_key';

  static final AppDatabase _instance = AppDatabase._internal();
  static Database? _database;
  static Future<Database>? _opening;

  factory AppDatabase() => _instance;

  AppDatabase._internal();

  Future<Database> get database async {
    if (_database?.isOpen ?? false) return _database!;
    _database = null;
    final opening = _opening ??= _initDatabase();
    try {
      _database = await opening;
      return _database!;
    } finally {
      if (identical(_opening, opening)) _opening = null;
    }
  }

  Future<Database> _initDatabase() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(databaseModeKey) ?? localMode;
    if (mode == remoteMode) {
      return RemoteDatabase.connect(
        serverUrl: prefs.getString(databaseServerUrlKey) ?? '',
        token: prefs.getString(databaseServerTokenKey) ?? '',
      );
    }
    if (mode == supabaseMode) {
      final service = SupabaseService();
      await service.configure(
        projectUrl:
            prefs.getString(supabaseProjectUrlKey) ?? SupabaseConfig.projectUrl,
        publishableKey: prefs.getString(supabasePublishableKeyKey) ??
            SupabaseConfig.publishableKey,
      );
      return SupabaseDatabase.connect(service: service);
    }
    final path = await getDatabasePath();

    final useSharedDatabase = await isUsingSharedDatabase();
    if (useSharedDatabase) {
      final file = File(path);
      if (!await file.exists()) {
        throw FileSystemException(
          'O banco compartilhado não foi encontrado. Verifique se o PC principal está ligado e se a pasta está compartilhada.',
          path,
        );
      }
    }

    print('Banco de dados em: $path');

    return await openDatabase(
      path,
      version: 29,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.rawQuery('PRAGMA busy_timeout = 10000');
        if (useSharedDatabase) {
          await _validateWriteAccess(db);
        }
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    print('Criando banco de dados...');

    // ==================== TABELAS PRINCIPAIS ====================

    // 1. Clientes
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT UNIQUE,
        name TEXT NOT NULL,
        document TEXT,
        phone TEXT,
        email TEXT,
        address TEXT,
        observations TEXT,
        total_purchases REAL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');

    // 2. Produtos - COM composicao_id
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo TEXT UNIQUE NOT NULL,
        nome TEXT NOT NULL,
        descricao TEXT,
        categoria TEXT NOT NULL,
        preco REAL NOT NULL,
        cost REAL DEFAULT 0,
        estoque REAL DEFAULT 0,
        unidade TEXT DEFAULT 'un',
        ativo INTEGER DEFAULT 1,
        composicao_id INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 3. Insumos
    await db.execute('''
      CREATE TABLE insumos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        codigo TEXT UNIQUE NOT NULL,
        nome TEXT NOT NULL,
        categoria TEXT NOT NULL,
        quantidade REAL DEFAULT 0,
        unidade TEXT DEFAULT 'un',
        preco_unitario REAL DEFAULT 0,
        fornecedor TEXT,
        estoque_minimo REAL DEFAULT 0,
        estoque_maximo REAL DEFAULT 0,
        observacoes TEXT,
        active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 4. Vendedores
    await db.execute('''
      CREATE TABLE sellers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        commission REAL DEFAULT 5,
        total_sales REAL DEFAULT 0,
        active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 5. Fornecedores
    await db.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        document TEXT,
        phone TEXT,
        email TEXT,
        address TEXT,
        product TEXT,
        active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 6. Funcionários
    await db.execute('''
      CREATE TABLE employees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        document TEXT,
        phone TEXT,
        email TEXT,
        position TEXT NOT NULL,
        salary REAL,
        hire_date TEXT NOT NULL,
        active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 7. Ordens de Serviço
    await db.execute('''
      CREATE TABLE orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        number TEXT UNIQUE NOT NULL,
        tipo TEXT NOT NULL,
        cliente_nome TEXT,
        customer_id INTEGER NOT NULL,
        seller_id INTEGER,
        total REAL NOT NULL,
        discount REAL DEFAULT 0,
        entrada REAL DEFAULT 0,
        parcelas TEXT,
        parcelas_datas TEXT,
        valor_manual REAL DEFAULT 0,
        prioridade TEXT DEFAULT 'normal',
        payment_method TEXT NOT NULL,
        status TEXT NOT NULL,
        observations TEXT,
        delivery_date TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id),
        FOREIGN KEY (seller_id) REFERENCES sellers (id)
      )
    ''');

    await _createPurchaseOrdersTable(db);

    // 8. Itens do Pedido
    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        subtotal REAL NOT NULL,
        specifications TEXT,
        largura REAL DEFAULT 0,
        altura REAL DEFAULT 0,
        custo_unitario REAL DEFAULT 0,
        detalhes_custo TEXT,
        terceirizado INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (id)
      )
    ''');

    // 9. Financeiro
    await db.execute('''
      CREATE TABLE financial (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        description TEXT NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        due_date TEXT NOT NULL,
        is_paid INTEGER DEFAULT 0,
        notes TEXT,
        order_id INTEGER,
        customer_id INTEGER,
        customer_name TEXT,
        categoria TEXT DEFAULT 'outros',
        forma_pagamento TEXT DEFAULT '',
        parcela INTEGER DEFAULT 0,
        total_parcelas INTEGER DEFAULT 0,
        valor_bruto REAL DEFAULT 0,
        taxa REAL DEFAULT 0,
        valor_liquido REAL DEFAULT 0,
        status TEXT DEFAULT 'pendente',
        pagamentos TEXT DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 10. Movimentações de Estoque
    await db.execute('''
      CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        type TEXT NOT NULL,
        previous_stock REAL NOT NULL,
        new_stock REAL NOT NULL,
        reason TEXT NOT NULL,
        order_id INTEGER,
        supplier_id INTEGER,
        user_id INTEGER,
        created_at TEXT NOT NULL
      )
    ''');

    // 11. Pontos
    await db.execute('''
      CREATE TABLE pontos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL,
        employee_name TEXT NOT NULL,
        data TEXT NOT NULL,
        entrada1 TEXT,
        saida1 TEXT,
        entrada2 TEXT,
        saida2 TEXT,
        horas_trabalhadas REAL DEFAULT 0,
        horas_extras REAL DEFAULT 0,
        observacoes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (employee_id) REFERENCES employees (id)
      )
    ''');

    // 12. Holerites
    await db.execute('''
      CREATE TABLE holerites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id INTEGER NOT NULL,
        employee_name TEXT NOT NULL,
        mes_referencia TEXT NOT NULL,
        salario_base REAL DEFAULT 0,
        horas_trabalhadas REAL DEFAULT 0,
        horas_extras REAL DEFAULT 0,
        valor_hora REAL DEFAULT 0,
        valor_hora_extra REAL DEFAULT 0,
        total_horas_extras REAL DEFAULT 0,
        salario_bruto REAL DEFAULT 0,
        descontos REAL DEFAULT 0,
        vale_transporte REAL DEFAULT 0,
        vale_alimentacao REAL DEFAULT 0,
        insalubridade REAL DEFAULT 0,
        periculosidade REAL DEFAULT 0,
        comissao REAL DEFAULT 0,
        outros REAL DEFAULT 0,
        inss REAL DEFAULT 0,
        irrf REAL DEFAULT 0,
        salario_liquido REAL DEFAULT 0,
        observacoes TEXT,
        pago INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (employee_id) REFERENCES employees (id)
      )
    ''');

    // ==================== TABELAS CORTE A LASER ====================

    // 13. Materiais
    await db.execute('''
      CREATE TABLE materiais (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        codigo TEXT UNIQUE NOT NULL,
        categoria TEXT NOT NULL,
        tipo TEXT NOT NULL,
        cor TEXT,
        acabamento TEXT,
        espessura REAL DEFAULT 0,
        largura_chapa REAL DEFAULT 0,
        altura_chapa REAL DEFAULT 0,
        area_chapa REAL DEFAULT 0,
        preco_chapa REAL DEFAULT 0,
        preco_por_m2 REAL DEFAULT 0,
        preco_unidade REAL DEFAULT 0,
        preco_venda REAL DEFAULT 0,
        unidade TEXT DEFAULT 'un',
        perda_padrao REAL DEFAULT 0,
        quantidade_estoque REAL DEFAULT 0,
        estoque_minimo REAL DEFAULT 0,
        estoque_maximo REAL DEFAULT 0,
        fornecedor TEXT,
        observacoes TEXT,
        active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 14. Máquinas
    await db.execute('''
      CREATE TABLE maquinas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        tipo TEXT NOT NULL,
        modelo TEXT,
        fabricante TEXT,
        area_util_largura REAL DEFAULT 0,
        area_util_altura REAL DEFAULT 0,
        area_util REAL DEFAULT 0,
        custo_energia_hora REAL DEFAULT 0,
        custo_manutencao_hora REAL DEFAULT 0,
        custo_depreciacao_hora REAL DEFAULT 0,
        custo_operador_hora REAL DEFAULT 0,
        custo_outros_hora REAL DEFAULT 0,
        custo_total_hora REAL DEFAULT 0,
        custo_total_minuto REAL DEFAULT 0,
        velocidade_maxima REAL DEFAULT 0,
        potencia REAL DEFAULT 0,
        consumo_energia REAL DEFAULT 0,
        observacoes TEXT,
        active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 15. Retalhos
    await db.execute('''
      CREATE TABLE retalhos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        material_id INTEGER NOT NULL,
        codigo TEXT UNIQUE NOT NULL,
        nome TEXT NOT NULL,
        largura REAL DEFAULT 0,
        altura REAL DEFAULT 0,
        area REAL DEFAULT 0,
        pedido_origem_id INTEGER,
        pedido_origem_numero TEXT,
        localizacao TEXT,
        prateleira TEXT,
        valor_estimado REAL DEFAULT 0,
        valor_venda REAL DEFAULT 0,
        status TEXT DEFAULT 'disponivel',
        observacoes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (material_id) REFERENCES materiais (id)
      )
    ''');

    // 16. Composições
    await db.execute('''
      CREATE TABLE composicoes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pedido_id INTEGER,
        orcamento_id INTEGER,
        produto_id INTEGER,
        custo_total_materiais REAL DEFAULT 0,
        custo_total_maquinas REAL DEFAULT 0,
        custo_total_servicos REAL DEFAULT 0,
        custo_total REAL DEFAULT 0,
        margem_lucro REAL DEFAULT 0,
        preco_venda REAL DEFAULT 0,
        observacoes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 17. Itens da Composição
    await db.execute('''
      CREATE TABLE composicao_itens (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        composicao_id INTEGER NOT NULL,
        tipo TEXT NOT NULL,
        descricao TEXT NOT NULL,
        quantidade REAL DEFAULT 0,
        unidade TEXT,
        valor_unitario REAL DEFAULT 0,
        valor_total REAL DEFAULT 0,
        observacoes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (composicao_id) REFERENCES composicoes (id) ON DELETE CASCADE
      )
    ''');

    // 18. Agenda de acompanhamentos e mensagens
    await db.execute('''
      CREATE TABLE agenda_followups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cliente_nome TEXT NOT NULL,
        telefone TEXT DEFAULT '',
        assunto TEXT NOT NULL,
        observacoes TEXT DEFAULT '',
        status TEXT NOT NULL DEFAULT 'responder',
        periodicidade TEXT NOT NULL DEFAULT 'unico',
        agendado_para TEXT NOT NULL,
        concluido_em TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 19. Usuários e permissões de acesso
    await db.execute('''
      CREATE TABLE system_users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL COLLATE NOCASE,
        full_name TEXT NOT NULL,
        email TEXT DEFAULT '',
        password TEXT NOT NULL,
        is_admin INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        permissions TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.insert('system_users', {
      'username': 'admin',
      'full_name': 'Administrador do Sistema',
      'email': 'admin@matterdi.com',
      'password': 'admin123',
      'is_admin': 1,
      'active': 1,
      'permissions': '[]',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    await createErpModulesSchema(db);
    await _createIndexes(db);
    print('Banco de dados criado com sucesso!');
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_codigo ON products(codigo)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_nome ON products(nome)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_orders_number ON orders(number)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_financial_due_date ON financial(due_date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_financial_customer_id ON financial(customer_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_financial_order_id ON financial(order_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_employees_name ON employees(name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_suppliers_name ON suppliers(name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_insumos_codigo ON insumos(codigo)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pontos_employee_id ON pontos(employee_id)');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_pontos_data ON pontos(data)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_holerites_employee_id ON holerites(employee_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_holerites_mes ON holerites(mes_referencia)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_materiais_nome ON materiais(nome)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_materiais_codigo ON materiais(codigo)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_materiais_categoria ON materiais(categoria)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_maquinas_nome ON maquinas(nome)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_maquinas_tipo ON maquinas(tipo)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_retalhos_status ON retalhos(status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_retalhos_material_id ON retalhos(material_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_composicoes_pedido_id ON composicoes(pedido_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_composicao_itens_composicao_id ON composicao_itens(composicao_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_agenda_followups_date ON agenda_followups(agendado_para)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_agenda_followups_status ON agenda_followups(status)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_system_users_username ON system_users(username COLLATE NOCASE)');
  }

  // MIGRAÇÃO COMPLETA
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 29) {
      await _createPurchaseOrdersTable(db);
    }
    if (oldVersion < 28) {
      await createErpModulesSchema(db);
    }
    if (oldVersion < 27) {
      final columns = await db.rawQuery('PRAGMA table_info(order_items)');
      final hasTerceirizado =
          columns.any((column) => column['name'] == 'terceirizado');
      if (!hasTerceirizado) {
        await db.execute(
          'ALTER TABLE order_items ADD COLUMN terceirizado INTEGER NOT NULL DEFAULT 0',
        );
      }
    }

    // A partir da versão 26, as dimensões dos itens de venda são armazenadas
    // em milímetros. Os registros anteriores eram armazenados em centímetros.
    if (oldVersion < 26) {
      await db.execute('''
        UPDATE order_items
        SET largura = largura * 10,
            altura = altura * 10
        WHERE largura > 0 OR altura > 0
      ''');
    }
    if (oldVersion < 25) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS system_users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT UNIQUE NOT NULL COLLATE NOCASE,
          full_name TEXT NOT NULL,
          email TEXT DEFAULT '',
          password TEXT NOT NULL,
          is_admin INTEGER NOT NULL DEFAULT 0,
          active INTEGER NOT NULL DEFAULT 1,
          permissions TEXT NOT NULL DEFAULT '[]',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      final adminExists = await db.query(
        'system_users',
        columns: ['id'],
        where: 'username = ?',
        whereArgs: ['admin'],
        limit: 1,
      );
      if (adminExists.isEmpty) {
        await db.insert('system_users', {
          'username': 'admin',
          'full_name': 'Administrador do Sistema',
          'email': 'admin@matterdi.com',
          'password': 'admin123',
          'is_admin': 1,
          'active': 1,
          'permissions': '[]',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_system_users_username ON system_users(username COLLATE NOCASE)');
    }
    if (oldVersion < 24) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS agenda_followups (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          cliente_nome TEXT NOT NULL,
          telefone TEXT DEFAULT '',
          assunto TEXT NOT NULL,
          observacoes TEXT DEFAULT '',
          status TEXT NOT NULL DEFAULT 'responder',
          periodicidade TEXT NOT NULL DEFAULT 'unico',
          agendado_para TEXT NOT NULL,
          concluido_em TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_agenda_followups_date ON agenda_followups(agendado_para)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_agenda_followups_status ON agenda_followups(status)');
    }
    if (oldVersion < 23) {
      final columns = await db.rawQuery('PRAGMA table_info(order_items)');
      if (!columns.any((column) => column['name'] == 'custo_unitario')) {
        await db.execute(
            'ALTER TABLE order_items ADD COLUMN custo_unitario REAL DEFAULT 0');
      }
      if (!columns.any((column) => column['name'] == 'detalhes_custo')) {
        await db
            .execute('ALTER TABLE order_items ADD COLUMN detalhes_custo TEXT');
      }
    }
    print('Migrando banco de $oldVersion para $newVersion');

    // MIGRAÇÃO PARA ADICIONAR composicao_id (versão 22)
    if (oldVersion < 22) {
      try {
        // Verificar se a coluna já existe
        final columns = await db.rawQuery(
          "PRAGMA table_info(products)",
        );
        final hasComposicaoId =
            columns.any((col) => col['name'] == 'composicao_id');

        if (!hasComposicaoId) {
          await db.execute(
            'ALTER TABLE products ADD COLUMN composicao_id INTEGER',
          );
          print('Coluna composicao_id adicionada na tabela products');
        } else {
          print('Coluna composicao_id já existe');
        }
      } catch (e) {
        print('Erro ao adicionar composicao_id: $e');
      }
    }

    // MIGRAÇÃO PARA ADICIONAR produto_id na composicoes (versão 22)
    if (oldVersion < 22) {
      try {
        final columns = await db.rawQuery(
          "PRAGMA table_info(composicoes)",
        );
        final hasProdutoId = columns.any((col) => col['name'] == 'produto_id');

        if (!hasProdutoId) {
          await db.execute(
            'ALTER TABLE composicoes ADD COLUMN produto_id INTEGER',
          );
          print('Coluna produto_id adicionada na tabela composicoes');
        } else {
          print('Coluna produto_id já existe');
        }
      } catch (e) {
        print('Erro ao adicionar produto_id: $e');
      }
    }

    // MIGRAÇÃO PARA ADICIONAR preco_venda na materiais (versão 21)
    if (oldVersion < 21) {
      try {
        final columns = await db.rawQuery(
          "PRAGMA table_info(materiais)",
        );
        final hasPrecoVenda =
            columns.any((col) => col['name'] == 'preco_venda');

        if (!hasPrecoVenda) {
          await db.execute(
            'ALTER TABLE materiais ADD COLUMN preco_venda REAL DEFAULT 0',
          );
          print('Coluna preco_venda adicionada na tabela materiais');
        } else {
          print('Coluna preco_venda já existe');
        }
      } catch (e) {
        print('Erro ao adicionar preco_venda: $e');
      }
    }

    // MIGRAÇÃO: Renomear colunas da tabela products (versão 20)
    if (oldVersion < 20) {
      try {
        // Verificar se a tabela products existe no formato antigo
        final columns = await db.rawQuery(
          "PRAGMA table_info(products)",
        );
        final hasCode = columns.any((col) => col['name'] == 'code');

        if (hasCode) {
          // Criar nova tabela com estrutura correta
          await db.execute('''
            CREATE TABLE products_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              codigo TEXT UNIQUE NOT NULL,
              nome TEXT NOT NULL,
              descricao TEXT,
              categoria TEXT NOT NULL,
              preco REAL NOT NULL,
              cost REAL DEFAULT 0,
              estoque REAL DEFAULT 0,
              unidade TEXT DEFAULT 'un',
              ativo INTEGER DEFAULT 1,
              composicao_id INTEGER,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');

          // Copiar dados da tabela antiga
          await db.execute('''
            INSERT INTO products_new (id, codigo, nome, descricao, categoria, preco, cost, estoque, unidade, ativo, composicao_id, created_at, updated_at)
            SELECT id, code, name, description, category, price, cost, stock, unit, active, NULL, created_at, updated_at
            FROM products
          ''');

          // Remover tabela antiga
          await db.execute('DROP TABLE products');

          // Renomear nova tabela
          await db.execute('ALTER TABLE products_new RENAME TO products');

          print('Tabela products migrada com sucesso!');
        } else {
          print('Tabela products já está no formato correto');
        }
      } catch (e) {
        print('Erro na migração da tabela products: $e');
      }
    }

    // Outras migrações existentes...
    if (oldVersion < 19) {
      try {
        await db.execute(
            'ALTER TABLE products ADD COLUMN valor_minuto_maquina REAL DEFAULT 0');
      } catch (e) {}
      try {
        await db.execute(
            'ALTER TABLE products ADD COLUMN tempo_estimado REAL DEFAULT 0');
      } catch (e) {}
    }

    if (oldVersion < 18) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS materiais (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nome TEXT NOT NULL,
            codigo TEXT UNIQUE NOT NULL,
            categoria TEXT NOT NULL,
            tipo TEXT NOT NULL,
            cor TEXT,
            acabamento TEXT,
            espessura REAL DEFAULT 0,
            largura_chapa REAL DEFAULT 0,
            altura_chapa REAL DEFAULT 0,
            area_chapa REAL DEFAULT 0,
            preco_chapa REAL DEFAULT 0,
            preco_por_m2 REAL DEFAULT 0,
            preco_unidade REAL DEFAULT 0,
            unidade TEXT DEFAULT 'un',
            perda_padrao REAL DEFAULT 0,
            quantidade_estoque REAL DEFAULT 0,
            estoque_minimo REAL DEFAULT 0,
            estoque_maximo REAL DEFAULT 0,
            fornecedor TEXT,
            observacoes TEXT,
            active INTEGER DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      } catch (e) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS maquinas (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nome TEXT NOT NULL,
            tipo TEXT NOT NULL,
            modelo TEXT,
            fabricante TEXT,
            area_util_largura REAL DEFAULT 0,
            area_util_altura REAL DEFAULT 0,
            area_util REAL DEFAULT 0,
            custo_energia_hora REAL DEFAULT 0,
            custo_manutencao_hora REAL DEFAULT 0,
            custo_depreciacao_hora REAL DEFAULT 0,
            custo_operador_hora REAL DEFAULT 0,
            custo_outros_hora REAL DEFAULT 0,
            custo_total_hora REAL DEFAULT 0,
            custo_total_minuto REAL DEFAULT 0,
            velocidade_maxima REAL DEFAULT 0,
            potencia REAL DEFAULT 0,
            consumo_energia REAL DEFAULT 0,
            observacoes TEXT,
            active INTEGER DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      } catch (e) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS retalhos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            material_id INTEGER NOT NULL,
            codigo TEXT UNIQUE NOT NULL,
            nome TEXT NOT NULL,
            largura REAL DEFAULT 0,
            altura REAL DEFAULT 0,
            area REAL DEFAULT 0,
            pedido_origem_id INTEGER,
            pedido_origem_numero TEXT,
            localizacao TEXT,
            prateleira TEXT,
            valor_estimado REAL DEFAULT 0,
            valor_venda REAL DEFAULT 0,
            status TEXT DEFAULT 'disponivel',
            observacoes TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (material_id) REFERENCES materiais (id)
          )
        ''');
      } catch (e) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS composicoes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pedido_id INTEGER,
            orcamento_id INTEGER,
            custo_total_materiais REAL DEFAULT 0,
            custo_total_maquinas REAL DEFAULT 0,
            custo_total_servicos REAL DEFAULT 0,
            custo_total REAL DEFAULT 0,
            margem_lucro REAL DEFAULT 0,
            preco_venda REAL DEFAULT 0,
            observacoes TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      } catch (e) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS composicao_itens (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            composicao_id INTEGER NOT NULL,
            tipo TEXT NOT NULL,
            descricao TEXT NOT NULL,
            quantidade REAL DEFAULT 0,
            unidade TEXT,
            valor_unitario REAL DEFAULT 0,
            valor_total REAL DEFAULT 0,
            observacoes TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY (composicao_id) REFERENCES composicoes (id) ON DELETE CASCADE
          )
        ''');
      } catch (e) {}
    }

    if (oldVersion < 17) {
      try {
        await db.execute('ALTER TABLE employees ADD COLUMN document TEXT');
      } catch (e) {}
    }

    if (oldVersion < 16) {
      try {
        await db.execute(
            'ALTER TABLE financial ADD COLUMN pagamentos TEXT DEFAULT ""');
      } catch (e) {}
    }

    if (oldVersion < 15) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS pontos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            employee_id INTEGER NOT NULL,
            employee_name TEXT NOT NULL,
            data TEXT NOT NULL,
            entrada1 TEXT,
            saida1 TEXT,
            entrada2 TEXT,
            saida2 TEXT,
            horas_trabalhadas REAL DEFAULT 0,
            horas_extras REAL DEFAULT 0,
            observacoes TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (employee_id) REFERENCES employees (id)
          )
        ''');
      } catch (e) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS holerites (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            employee_id INTEGER NOT NULL,
            employee_name TEXT NOT NULL,
            mes_referencia TEXT NOT NULL,
            salario_base REAL DEFAULT 0,
            horas_trabalhadas REAL DEFAULT 0,
            horas_extras REAL DEFAULT 0,
            valor_hora REAL DEFAULT 0,
            valor_hora_extra REAL DEFAULT 0,
            total_horas_extras REAL DEFAULT 0,
            salario_bruto REAL DEFAULT 0,
            descontos REAL DEFAULT 0,
            vale_transporte REAL DEFAULT 0,
            vale_alimentacao REAL DEFAULT 0,
            insalubridade REAL DEFAULT 0,
            periculosidade REAL DEFAULT 0,
            comissao REAL DEFAULT 0,
            outros REAL DEFAULT 0,
            inss REAL DEFAULT 0,
            irrf REAL DEFAULT 0,
            salario_liquido REAL DEFAULT 0,
            observacoes TEXT,
            pago INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (employee_id) REFERENCES employees (id)
          )
        ''');
      } catch (e) {}
    }

    if (oldVersion < 14) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS insumos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            codigo TEXT UNIQUE NOT NULL,
            nome TEXT NOT NULL,
            categoria TEXT NOT NULL,
            quantidade REAL DEFAULT 0,
            unidade TEXT DEFAULT 'un',
            preco_unitario REAL DEFAULT 0,
            fornecedor TEXT,
            estoque_minimo REAL DEFAULT 0,
            estoque_maximo REAL DEFAULT 0,
            observacoes TEXT,
            active INTEGER DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      } catch (e) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS stock_movements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id INTEGER NOT NULL,
            product_name TEXT NOT NULL,
            quantity REAL NOT NULL,
            type TEXT NOT NULL,
            previous_stock REAL NOT NULL,
            new_stock REAL NOT NULL,
            reason TEXT NOT NULL,
            order_id INTEGER,
            supplier_id INTEGER,
            user_id INTEGER,
            created_at TEXT NOT NULL
          )
        ''');
      } catch (e) {}
    }

    if (oldVersion < 13) {
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN parcelas_datas TEXT');
      } catch (e) {}
    }

    if (oldVersion < 12) {
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN seller_id INTEGER');
      } catch (e) {}
    }

    if (oldVersion < 11) {
      try {
        await db.execute('ALTER TABLE products ADD COLUMN cost REAL DEFAULT 0');
      } catch (e) {}
    }

    print('Migrações concluídas!');
  }

  Future<void> _createPurchaseOrdersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        number TEXT UNIQUE NOT NULL,
        supplier_id INTEGER,
        supplier_name TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'solicitado',
        expected_date TEXT,
        items TEXT NOT NULL DEFAULT '[]',
        notes TEXT NOT NULL DEFAULT '',
        total REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers (id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchase_orders_status ON purchase_orders(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier ON purchase_orders(supplier_id)',
    );
  }

  // ==================== MÉTODOS DE UTILIDADE ====================

  Future<void> close() async {
    if (_opening != null) {
      try {
        await _opening;
      } catch (_) {
        // Uma tentativa de conexão que falhou não impede trocar o servidor.
      }
    }
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<bool> databaseExists() async {
    if (await isUsingExternalDatabase()) {
      return (await database).isOpen;
    }
    final path = await getDatabasePath();
    return File(path).exists();
  }

  Future<String> getDatabasePath() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(databaseModeKey) ?? localMode;
    if (mode == remoteMode || mode == supabaseMode) {
      throw StateError(
        'O banco está na nuvem. Gerencie os dados e backups no servidor.',
      );
    }
    final sharedPath = prefs.getString(databasePathKey)?.trim();
    if (mode == sharedMode && sharedPath != null && sharedPath.isNotEmpty) {
      return normalize(absolute(sharedPath));
    }

    const databaseName = 'matterdi_sistem.db';
    if (Platform.isAndroid) {
      final databaseDirectory = await getDatabasesPath();
      await Directory(databaseDirectory).create(recursive: true);
      final databasePath = join(databaseDirectory, databaseName);
      final databaseFile = File(databasePath);

      // Preserve o banco criado por versões anteriores na pasta de documentos.
      if (!await databaseFile.exists()) {
        try {
          final documentsDirectory = await getApplicationDocumentsDirectory();
          final oldDatabaseFile =
              File(join(documentsDirectory.path, databaseName));
          if (await oldDatabaseFile.exists()) {
            await oldDatabaseFile.copy(databasePath);
          }
        } catch (error) {
          print('Não foi possível procurar o banco antigo do Android: $error');
        }
      }

      return databasePath;
    }

    final directory = await getApplicationDocumentsDirectory();
    return join(directory.path, databaseName);
  }

  Future<bool> isUsingSharedDatabase() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(databaseModeKey) ?? localMode) == sharedMode;
  }

  Future<bool> isUsingRemoteDatabase() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(databaseModeKey);
    return mode == remoteMode || mode == supabaseMode;
  }

  Future<bool> isUsingSupabaseDatabase() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(databaseModeKey) == supabaseMode;
  }

  Future<bool> isUsingExternalDatabase() => isUsingRemoteDatabase();

  Future<void> testSupabaseConnection({
    required String projectUrl,
    required String publishableKey,
  }) =>
      SupabaseService().testConnection(
        projectUrl: projectUrl,
        publishableKey: publishableKey,
      );

  Future<void> configureSupabaseDatabase({
    required String projectUrl,
    required String publishableKey,
  }) async {
    final normalizedUrl = SupabaseService.normalizeProjectUrl(projectUrl);
    final validatedKey = SupabaseService.validatePublishableKey(publishableKey);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('database_server_enabled') ?? false) {
      throw StateError('Desative o servidor deste PC antes de trocar o banco.');
    }

    await testSupabaseConnection(
      projectUrl: normalizedUrl,
      publishableKey: validatedKey,
    );

    final previousMode = prefs.getString(databaseModeKey) ?? localMode;
    final previousUrl = prefs.getString(supabaseProjectUrlKey);
    final previousKey = prefs.getString(supabasePublishableKeyKey);
    final service = SupabaseService();
    await close();
    try {
      await prefs.setString(supabaseProjectUrlKey, normalizedUrl);
      await prefs.setString(supabasePublishableKeyKey, validatedKey);
      await prefs.setString(databaseModeKey, supabaseMode);
      await service.configure(
        projectUrl: normalizedUrl,
        publishableKey: validatedKey,
      );
      _database = await SupabaseDatabase.connect(service: service);
    } catch (_) {
      await close();
      await prefs.setString(databaseModeKey, previousMode);
      if (previousUrl == null) {
        await prefs.remove(supabaseProjectUrlKey);
      } else {
        await prefs.setString(supabaseProjectUrlKey, previousUrl);
      }
      if (previousKey == null) {
        await prefs.remove(supabasePublishableKeyKey);
      } else {
        await prefs.setString(supabasePublishableKeyKey, previousKey);
      }
      if (previousMode == supabaseMode &&
          previousUrl != null &&
          previousKey != null) {
        await service.configure(
          projectUrl: previousUrl,
          publishableKey: previousKey,
        );
      }
      rethrow;
    }
  }

  Future<void> testRemoteConnection({
    required String serverUrl,
    required String token,
  }) async {
    final remote = await RemoteDatabase.connect(
      serverUrl: serverUrl,
      token: token,
    );
    await remote.close();
  }

  Future<void> configureRemoteDatabase({
    required String serverUrl,
    required String token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('database_server_enabled') ?? false) {
      throw StateError('Desative o servidor deste PC antes de trocar o banco.');
    }
    final remote = await RemoteDatabase.connect(
      serverUrl: serverUrl,
      token: token,
    );
    final previousMode = prefs.getString(databaseModeKey) ?? localMode;
    final previousUrl = prefs.getString(databaseServerUrlKey);
    final previousToken = prefs.getString(databaseServerTokenKey);
    try {
      await close();
      await prefs.setString(databaseServerUrlKey, remote.path);
      await prefs.setString(databaseServerTokenKey, token.trim());
      await prefs.setString(databaseModeKey, remoteMode);
      _database = remote;
    } catch (_) {
      await remote.close();
      await prefs.setString(databaseModeKey, previousMode);
      if (previousUrl == null) {
        await prefs.remove(databaseServerUrlKey);
      } else {
        await prefs.setString(databaseServerUrlKey, previousUrl);
      }
      if (previousToken == null) {
        await prefs.remove(databaseServerTokenKey);
      } else {
        await prefs.setString(databaseServerTokenKey, previousToken);
      }
      rethrow;
    }
  }

  Future<void> configureDatabase({
    required bool useSharedDatabase,
    String? sharedPath,
  }) async {
    final normalizedPath = sharedPath?.trim();
    if (useSharedDatabase) {
      if (normalizedPath == null || normalizedPath.isEmpty) {
        throw ArgumentError('Selecione o arquivo do banco de dados principal.');
      }
      await validateDatabaseFile(normalizedPath, requireWriteAccess: true);
    }

    final prefs = await SharedPreferences.getInstance();
    final previousMode = prefs.getString(databaseModeKey) ?? localMode;
    final previousPath = prefs.getString(databasePathKey);
    final newMode = useSharedDatabase ? sharedMode : localMode;
    final newPath = normalizedPath == null || normalizedPath.isEmpty
        ? null
        : normalize(absolute(normalizedPath));

    final sameMode = previousMode == newMode;
    final samePath = !useSharedDatabase ||
        previousPath?.toLowerCase() == newPath?.toLowerCase();
    if (sameMode && samePath) {
      await database;
      return;
    }

    if (prefs.getBool('database_server_enabled') ?? false) {
      throw StateError('Desative o servidor deste PC antes de trocar o banco.');
    }

    await close();
    try {
      await prefs.setString(databaseModeKey, newMode);
      if (newPath != null) {
        await prefs.setString(databasePathKey, newPath);
      }

      // Abre agora para detectar problemas antes de confirmar ao usuário.
      await database;
    } catch (_) {
      await close();
      await prefs.setString(databaseModeKey, previousMode);
      if (previousPath == null) {
        await prefs.remove(databasePathKey);
      } else {
        await prefs.setString(databasePathKey, previousPath);
      }
      try {
        await database;
      } catch (_) {
        // Preserve o erro da nova configuração se o servidor antigo caiu.
      }
      rethrow;
    }
  }

  Future<void> validateDatabaseFile(
    String databasePath, {
    bool requireWriteAccess = false,
  }) async {
    final normalizedPath = normalize(absolute(databasePath.trim()));
    final file = File(normalizedPath);
    if (!await file.exists()) {
      throw FileSystemException(
          'Arquivo de banco de dados não encontrado', normalizedPath);
    }
    if (extension(normalizedPath).toLowerCase() != '.db') {
      throw const FormatException(
          'Selecione um arquivo de banco com extensão .db.');
    }

    Database? testDatabase;
    try {
      testDatabase = await openDatabase(
        normalizedPath,
        readOnly: !requireWriteAccess,
        singleInstance: false,
      );
      final result = await testDatabase.rawQuery('PRAGMA quick_check');
      if (result.isEmpty || result.first.values.first.toString() != 'ok') {
        throw const FormatException(
            'O arquivo selecionado não é um banco SQLite válido.');
      }
      final tables = await testDatabase.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name IN ('customers', 'products', 'orders')",
      );
      if (tables.length != 3) {
        throw const FormatException(
          'O arquivo não pertence ao MatterdiSistem ou está incompleto.',
        );
      }
      if (requireWriteAccess) {
        await testDatabase.rawQuery('PRAGMA busy_timeout = 10000');
        await _validateWriteAccess(testDatabase);
      }
    } finally {
      await testDatabase?.close();
    }
  }

  Future<void> _validateWriteAccess(Database db) async {
    try {
      await db.execute('BEGIN IMMEDIATE');
      try {
        final version = await db.getVersion();
        await db.setVersion(version);
      } finally {
        await db.execute('ROLLBACK');
      }
    } on DatabaseException catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('readonly') || message.contains('read-only')) {
        throw FileSystemException(
          'O banco compartilhado está disponível apenas para leitura. '
          'No PC principal, permita Alteração nas permissões de Compartilhamento '
          'e Modificar na aba Segurança da pasta para o usuário deste PC. '
          'A pasta e o arquivo .db precisam permitir gravação, inclusive a '
          'criação e exclusão dos arquivos auxiliares do SQLite. '
          'Depois, feche e abra o sistema e teste a conexão novamente.',
          db.path,
        );
      }
      rethrow;
    }
  }

  Future<int> getDatabaseSize() async {
    if (await isUsingExternalDatabase()) return 0;
    final path = await getDatabasePath();
    final file = File(path);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }
}
