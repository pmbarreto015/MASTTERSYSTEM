import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';

// Telas
import 'dashboard/dashboard_screen.dart';
import 'customers/customer_list_screen.dart';
import 'products/product_list_screen.dart';
import 'quote/quote_screen.dart';
import 'quote/quote_approval_screen.dart';
import 'order/orders_screen.dart';
import 'production/production_screen.dart';
import 'delivery/delivery_screen.dart';
import 'financial/financial_modules_screen.dart';
import 'suppliers/fornecedores_screen.dart';
import 'inventory/inventory_screen.dart';
import 'sales/vendedores_screen.dart';
import 'employees/hr_screen.dart';
import 'reports/relatorios_screen.dart';
import 'reports/rentabilidade_screen.dart';
import 'arquivo/arquivo_screen.dart';
import 'settings/settings_screen.dart';
import 'backup/backup_screen.dart';
import 'help/help_desk_screen.dart';
import 'agenda/agenda_screen.dart';

// IMPORTS DO CORTE A LASER
import 'corte_laser/materiais_screen.dart';
import 'corte_laser/maquinas_screen.dart';
import 'corte_laser/compositor_screen.dart';
import 'corte_laser/retalhos_screen.dart';
import 'corte_laser/aproveitamento_screen.dart';

class _FavoriteDestination {
  const _FavoriteDestination(
      this.index, this.title, this.icon, this.permission);
  final int index;
  final String title;
  final IconData icon;
  final String permission;
}

const _favoriteDestinations = [
  _FavoriteDestination(0, 'Dashboard', Icons.dashboard, 'dashboard'),
  _FavoriteDestination(17, 'Agenda', Icons.calendar_month, 'agenda'),
  _FavoriteDestination(
      19, 'Entregas', Icons.local_shipping_outlined, 'entregas'),
  _FavoriteDestination(3, 'Nova venda', Icons.shopping_cart, 'vendas'),
  _FavoriteDestination(15, 'Orçamentos', Icons.request_quote, 'orcamentos'),
  _FavoriteDestination(18, 'Pedidos', Icons.receipt_long, 'vendas'),
  _FavoriteDestination(4, 'Produção', Icons.factory, 'producao'),
  _FavoriteDestination(1, 'Clientes', Icons.people, 'clientes'),
  _FavoriteDestination(2, 'Produtos', Icons.inventory_2, 'produtos'),
  _FavoriteDestination(7, 'Estoque', Icons.inventory, 'estoque'),
  _FavoriteDestination(
      6, 'Fornecedores', Icons.business_outlined, 'fornecedores'),
  _FavoriteDestination(9, 'RH', Icons.people_outline, 'funcionarios'),
  _FavoriteDestination(8, 'Vendedores', Icons.person_outline, 'vendedores'),
  _FavoriteDestination(5, 'Financeiro', Icons.monetization_on, 'financeiro'),
  _FavoriteDestination(16, 'Rentabilidade', Icons.insights, 'rentabilidade'),
  _FavoriteDestination(11, 'Arquivos', Icons.folder_open, 'arquivos'),
  _FavoriteDestination(13, 'Backup', Icons.backup, 'backup'),
  _FavoriteDestination(12, 'Configurações', Icons.settings, 'configuracoes'),
  _FavoriteDestination(14, 'Suporte', Icons.help_outline, 'suporte'),
];

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentIndex = 0;
  final List<int> _navigationHistory = [];
  final Set<int> _visitedScreens = {};
  bool _drawerOpen = false;
  bool _permissionsInitialized = false;
  final Set<int> _favoriteIndexes = <int>{};
  static const _favoritesKey = 'main_screen_favorite_indexes_v1';

  static const _screenPermissions = [
    'dashboard',
    'clientes',
    'produtos',
    'vendas',
    'producao',
    'financeiro',
    'fornecedores',
    'estoque',
    'vendedores',
    'funcionarios',
    'relatorios',
    'arquivos',
    'configuracoes',
    'backup',
    'suporte',
    'orcamentos',
    'rentabilidade',
    'agenda',
    'vendas',
    'entregas',
  ];

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = List<Widget>.generate(
      _screenPermissions.length,
      _createScreen,
    );
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_favoritesKey) ?? const <String>[];
    if (!mounted) return;
    setState(() {
      _favoriteIndexes
        ..clear()
        ..addAll(values.map(int.tryParse).whereType<int>());
    });
  }

  Future<void> _toggleFavorite(int index) async {
    setState(() {
      if (!_favoriteIndexes.add(index)) _favoriteIndexes.remove(index);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _favoritesKey, _favoriteIndexes.map((item) => '$item').toList());
  }

  Widget _createScreen(int index) => switch (index) {
        0 => DashboardScreen(onNavigateToSection: _navigateTo),
        1 => const CustomerListScreen(),
        2 => const ProductListScreen(),
        3 => const QuoteScreen(),
        4 => const ProductionScreen(),
        5 => const FinancialModulesScreen(),
        6 => const FornecedoresScreen(),
        7 => const InventoryScreen(),
        8 => const VendedoresScreen(),
        9 => const HrScreen(),
        10 => const RelatoriosScreen(),
        11 => const ArquivoScreen(),
        12 => SettingsScreen(onBack: _goBack),
        13 => const BackupScreen(),
        14 => const HelpDeskScreen(),
        15 => const QuoteApprovalScreen(),
        16 => const RentabilidadeScreen(),
        17 => const AgendaScreen(),
        18 => const OrdersScreen(),
        19 => const DeliveryScreen(),
        _ => const SizedBox.shrink(),
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_permissionsInitialized) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final firstAllowed = _screenPermissions.indexWhere(auth.hasPermission);
    _currentIndex = firstAllowed;
    if (firstAllowed >= 0) _visitedScreens.add(firstAllowed);
    _permissionsInitialized = true;
  }

  void _navigateTo(int index, {bool rememberCurrent = true}) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (index < 0 ||
        index >= _screenPermissions.length ||
        !auth.hasPermission(_screenPermissions[index])) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seu usuário não possui acesso a esta função.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_currentIndex != index) FocusScope.of(context).unfocus();
    setState(() {
      if (rememberCurrent && _currentIndex >= 0 && _currentIndex != index) {
        _navigationHistory.add(_currentIndex);
      }
      _visitedScreens.add(index);
      _currentIndex = index;
    });
    _closeDrawerIfOpen();
  }

  void _goBack() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    while (_navigationHistory.isNotEmpty) {
      final index = _navigationHistory.removeLast();
      if (index != _currentIndex &&
          auth.hasPermission(_screenPermissions[index])) {
        _navigateTo(index, rememberCurrent: false);
        return;
      }
    }
    final homeIndex = _screenPermissions.indexWhere(auth.hasPermission);
    if (homeIndex >= 0 && homeIndex != _currentIndex) {
      _navigateTo(homeIndex, rememberCurrent: false);
    }
  }

  void _closeDrawerIfOpen() {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  // MÉTODO DE LOGOUT CORRIGIDO
  Future<void> _logout(BuildContext context) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final auth = Provider.of<AuthProvider>(context);
    final displayName = auth.currentUser?.fullName ?? 'Usuário';
    final userInitial = displayName.isEmpty ? 'U' : displayName.substring(0, 1);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final content = _currentIndex >= 0 &&
            auth.hasPermission(_screenPermissions[_currentIndex])
        ? IndexedStack(
            index: _currentIndex,
            children: List<Widget>.generate(_screens.length, (index) {
              // Mount sections only on their first visit and keep their drafts
              // alive. Hidden sections pause animations and automatic queries.
              return _visitedScreens.contains(index) &&
                      auth.hasPermission(_screenPermissions[index])
                  ? TickerMode(
                      enabled: index == _currentIndex,
                      child: ExcludeFocus(
                        excluding: index != _currentIndex,
                        child: _screens[index],
                      ),
                    )
                  : const SizedBox.shrink();
            }),
          )
        : const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app_outlined, size: 56, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'Escolha uma das funções liberadas no menu.',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );

    final homeIndex = _screenPermissions.indexWhere(auth.hasPermission);
    final canGoBack = _currentIndex != homeIndex ||
        _navigationHistory
            .any((index) => auth.hasPermission(_screenPermissions[index]));
    final favorites = _favoriteDestinations
        .where((item) =>
            _favoriteIndexes.contains(item.index) &&
            auth.hasPermission(item.permission))
        .toList();

    return PopScope<void>(
      canPop: _drawerOpen || !canGoBack,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_drawerOpen) _goBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        onDrawerChanged: (open) => setState(() => _drawerOpen = open),
        drawer: Drawer(
          width: screenWidth < 360 ? screenWidth * 0.9 : 320,
          child: _buildSidebar(
              isDark: isDark,
              displayName: displayName,
              userInitial: userInitial,
              width: screenWidth < 360 ? screenWidth * 0.9 : 320),
        ),
        appBar: AppBar(
          title: const Text('MastterSystem'),
          toolbarHeight: 48,
          backgroundColor:
              isDark ? const Color(0xFF1E1E1E) : const Color(0xFF0F62AC),
          foregroundColor: Colors.white,
          leading: Builder(
              builder: (context) => IconButton(
                    tooltip: 'Abrir menu',
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  )),
          bottom: favorites.isEmpty
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(42),
                  child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .12),
                          border: const Border(
                              top: BorderSide(color: Colors.white24))),
                      child: Row(children: [
                        const Padding(
                            padding: EdgeInsets.only(left: 12, right: 4),
                            child: Icon(Icons.star, size: 17)),
                        Expanded(
                            child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 5),
                                itemCount: favorites.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 6),
                                itemBuilder: (_, index) {
                                  final item = favorites[index];
                                  return ActionChip(
                                      avatar: Icon(item.icon, size: 16),
                                      label: Text(item.title),
                                      side: const BorderSide(
                                          color: Colors.white38),
                                      labelStyle: const TextStyle(
                                          color: Colors.white, fontSize: 12),
                                      onPressed: () => _navigateTo(item.index));
                                }))
                      ]))),
        ),
        body: content,
      ),
    );
  }

  Widget _buildSidebar({
    required bool isDark,
    required String displayName,
    required String userInitial,
    required double width,
  }) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFF0F62AC),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFF0A4B8C),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      'M',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F62AC),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                    child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MastterSystem',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'ERP',
                      style: TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ],
                )),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ..._buildOrderedMenu(isDark),
                  const SizedBox(height: 16),
                  Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.grey.shade800
                          : Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor:
                              Theme.of(context).colorScheme.surface,
                          child: Text(
                            userInitial,
                            style: const TextStyle(
                              color: Color(0xFF0F62AC),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const Text(
                                'Sair',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Sair',
                          icon: const Icon(
                            Icons.logout,
                            color: Colors.white70,
                            size: 16,
                          ),
                          onPressed: () => _logout(context),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildOrderedMenu(bool isDark) => [
        _buildMenuItem(
            icon: Icons.dashboard,
            title: 'Dashboard',
            index: 0,
            isDark: isDark,
            permission: 'dashboard'),
        _buildMenuItem(
            icon: Icons.calendar_month,
            title: 'Agenda',
            index: 17,
            isDark: isDark,
            permission: 'agenda'),
        _buildMenuItem(
            icon: Icons.local_shipping_outlined,
            title: 'Entregas e retiradas',
            index: 19,
            isDark: isDark,
            permission: 'entregas'),
        _buildMenuItem(
            icon: Icons.shopping_cart,
            title: 'Nova venda',
            index: 3,
            isDark: isDark,
            permission: 'vendas'),
        _buildMenuItem(
            icon: Icons.request_quote,
            title: 'Orçamentos',
            index: 15,
            isDark: isDark,
            permission: 'orcamentos'),
        _buildMenuItem(
            icon: Icons.receipt_long,
            title: 'Pedidos',
            index: 18,
            isDark: isDark,
            permission: 'vendas'),
        _buildMenuItem(
            icon: Icons.factory,
            title: 'Produção',
            index: 4,
            isDark: isDark,
            permission: 'producao'),
        _buildMenuItem(
            icon: Icons.people,
            title: 'Clientes',
            index: 1,
            isDark: isDark,
            permission: 'clientes'),
        _buildMenuItem(
            icon: Icons.inventory_2,
            title: 'Produtos',
            index: 2,
            isDark: isDark,
            permission: 'produtos'),
        _buildMenuItem(
            icon: Icons.inventory,
            title: 'Estoque',
            index: 7,
            isDark: isDark,
            permission: 'estoque'),
        _buildMenuItem(
            icon: Icons.business_outlined,
            title: 'Fornecedores e compras',
            index: 6,
            isDark: isDark,
            permission: 'fornecedores'),
        _buildSubmenuCorteLaser(isDark),
        _buildMenuItem(
            icon: Icons.people_outline,
            title: 'RH',
            index: 9,
            isDark: isDark,
            permission: 'funcionarios'),
        _buildMenuItem(
            icon: Icons.person_outline,
            title: 'Vendedores',
            index: 8,
            isDark: isDark,
            permission: 'vendedores'),
        _buildMenuItem(
            icon: Icons.monetization_on,
            title: 'Financeiro',
            index: 5,
            isDark: isDark,
            permission: 'financeiro'),
        _buildMenuItem(
            icon: Icons.insights,
            title: 'Rentabilidade',
            index: 16,
            isDark: isDark,
            permission: 'rentabilidade'),
        _buildMenuItem(
            icon: Icons.folder_open,
            title: 'Arquivos',
            index: 11,
            isDark: isDark,
            permission: 'arquivos'),
        _buildMenuItem(
            icon: Icons.backup,
            title: 'Backup',
            index: 13,
            isDark: isDark,
            permission: 'backup'),
        _buildMenuItem(
            icon: Icons.settings,
            title: 'Configurações',
            index: 12,
            isDark: isDark,
            permission: 'configuracoes'),
        _buildMenuItem(
            icon: Icons.help_outline,
            title: 'Suporte',
            index: 14,
            isDark: isDark,
            permission: 'suporte'),
      ];

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required int index,
    required bool isDark,
    required String permission,
  }) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.hasPermission(permission)) return const SizedBox.shrink();
    final isSelected = _currentIndex == index;

    return InkWell(
      onTap: () => _navigateTo(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? isDark
                  ? Colors.grey.shade700
                  : Colors.white.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? isDark
                      ? Colors.white
                      : Colors.white
                  : isDark
                      ? Colors.grey.shade400
                      : Colors.white70,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected
                      ? isDark
                          ? Colors.white
                          : Colors.white
                      : isDark
                          ? Colors.grey.shade400
                          : Colors.white70,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            IconButton(
              tooltip: _favoriteIndexes.contains(index)
                  ? 'Remover dos favoritos'
                  : 'Adicionar aos favoritos',
              onPressed: () => _toggleFavorite(index),
              icon: Icon(
                _favoriteIndexes.contains(index)
                    ? Icons.star
                    : Icons.star_border_outlined,
                size: 18,
              ),
              color: _favoriteIndexes.contains(index)
                  ? Colors.amber.shade300
                  : isDark
                      ? Colors.grey.shade500
                      : Colors.white54,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            ),
            if (isSelected)
              Container(
                width: 3,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // SUBMENU CORTE A LASER
  Widget _buildSubmenuCorteLaser(bool isDark) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    const laserPermissions = {
      'corte_materiais',
      'corte_maquinas',
      'corte_compositor',
      'corte_retalhos',
      'corte_aproveitamento',
    };
    if (!laserPermissions.any(auth.hasPermission)) {
      return const SizedBox.shrink();
    }
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
      ),
      child: ExpansionTile(
        leading: Icon(
          Icons.cut,
          color: isDark ? Colors.orange.shade300 : Colors.white70,
        ),
        title: Text(
          'Corte a Laser',
          style: TextStyle(
            color: isDark ? Colors.orange.shade300 : Colors.white70,
            fontSize: 13,
          ),
        ),
        iconColor: isDark ? Colors.orange.shade300 : Colors.white70,
        collapsedIconColor: isDark ? Colors.orange.shade300 : Colors.white70,
        children: [
          _buildSubMenuItem(
            icon: Icons.inventory_2,
            title: 'Materiais',
            onTap: () {
              _closeDrawerIfOpen();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MateriaisScreen()),
              );
            },
            isDark: isDark,
            permission: 'corte_materiais',
          ),
          _buildSubMenuItem(
            icon: Icons.precision_manufacturing,
            title: 'Máquinas',
            onTap: () {
              _closeDrawerIfOpen();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MaquinasScreen()),
              );
            },
            isDark: isDark,
            permission: 'corte_maquinas',
          ),
          _buildSubMenuItem(
            icon: Icons.calculate,
            title: 'Compositor',
            onTap: () {
              _closeDrawerIfOpen();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CompositorScreen()),
              );
            },
            isDark: isDark,
            permission: 'corte_compositor',
          ),
          _buildSubMenuItem(
            icon: Icons.recycling,
            title: 'Retalhos',
            onTap: () {
              _closeDrawerIfOpen();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RetalhosScreen()),
              );
            },
            isDark: isDark,
            permission: 'corte_retalhos',
          ),
          _buildSubMenuItem(
            icon: Icons.lightbulb,
            title: 'Aproveitamento',
            onTap: () {
              _closeDrawerIfOpen();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AproveitamentoScreen()),
              );
            },
            isDark: isDark,
            permission: 'corte_aproveitamento',
          ),
        ],
      ),
    );
  }

  Widget _buildSubMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required bool isDark,
    required String permission,
  }) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (!auth.hasPermission(permission)) return const SizedBox.shrink();
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDark ? Colors.grey.shade400 : Colors.white60,
              size: 16,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.white60,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
