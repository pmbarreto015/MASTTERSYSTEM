import 'package:flutter/material.dart';
import '../../core/background_refresh_mixin.dart';
import '../../core/database/app_database.dart';
import '../../core/supabase/supabase_service.dart';

import '../../constants/system_permissions.dart';
import '../../models/system_user_model.dart';
import '../../services/system_user_repository.dart';

class UserAccessSection extends StatefulWidget {
  const UserAccessSection({
    super.key,
    required this.isDark,
    this.repository,
  });

  final bool isDark;
  final SystemUserRepository? repository;

  @override
  State<UserAccessSection> createState() => _UserAccessSectionState();
}

class _UserAccessSectionState extends State<UserAccessSection>
    with BackgroundRefreshMixin<UserAccessSection> {
  late final SystemUserRepository _repository;
  List<SystemUserModel> _users = [];
  bool _loading = true;
  bool _usesSupabase = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SystemUserRepository();
    _loadUsers();
  }

  @override
  Future<void> refreshInBackground() => _loadUsers();

  Future<void> _loadUsers() async {
    if (!isRefreshingInBackground) setState(() => _loading = true);
    try {
      final usesSupabase = await AppDatabase().isUsingSupabaseDatabase();
      final users = await _repository.getAll();
      if (!mounted) return;
      setState(() {
        _users = users;
        _usesSupabase = usesSupabase;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Erro ao carregar usuários: $e', error: true);
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _openUserEditor({SystemUserModel? user}) async {
    if (user?.isAdmin ?? false) {
      await _openAdminPasswordEditor(user!);
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: user?.fullName ?? '');
    final usernameController =
        TextEditingController(text: user?.username ?? '');
    final emailController = TextEditingController(text: user?.email ?? '');
    final passwordController = TextEditingController();
    final selectedPermissions = {...?user?.permissions};
    var active = user?.active ?? true;
    var obscurePassword = true;

    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void applyPreset(Set<String> permissions) {
            setDialogState(() {
              selectedPermissions
                ..clear()
                ..addAll(permissions);
            });
          }

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.manage_accounts, color: Color(0xFF0F62AC)),
                const SizedBox(width: 10),
                Text(user == null ? 'Novo usuário' : 'Editar acesso'),
              ],
            ),
            content: SizedBox(
              width: 720,
              height: 620,
              child: Form(
                key: formKey,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'Nome do funcionário *',
                              prefixIcon: Icon(Icons.badge_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Informe o nome'
                                    : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: emailController,
                            decoration: const InputDecoration(
                              labelText: 'E-mail',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (!_usesSupabase) return null;
                              final email = value?.trim() ?? '';
                              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                  .hasMatch(email)) {
                                return 'Informe um e-mail válido';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: usernameController,
                            enabled: user == null,
                            decoration: const InputDecoration(
                              labelText: 'Usuário para entrar *',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Informe o usuário'
                                    : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: passwordController,
                            obscureText: obscurePassword,
                            decoration: InputDecoration(
                              labelText: user == null
                                  ? 'Senha *'
                                  : 'Nova senha (opcional)',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () => setDialogState(
                                  () => obscurePassword = !obscurePassword,
                                ),
                                icon: Icon(
                                  obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                              ),
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) {
                              final minimum = _usesSupabase ? 6 : 4;
                              if (user == null &&
                                  (value == null || value.length < minimum)) {
                                return 'Use pelo menos $minimum caracteres';
                              }
                              if (value != null &&
                                  value.isNotEmpty &&
                                  value.length < minimum) {
                                return 'Use pelo menos $minimum caracteres';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Atalhos:',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        OutlinedButton(
                          onPressed: () => applyPreset({
                            'vendas',
                            'orcamentos',
                          }),
                          child: const Text('Vendas + Orçamentos'),
                        ),
                        OutlinedButton(
                          onPressed: () => applyPreset({
                            'producao',
                            'corte_aproveitamento',
                          }),
                          child: const Text('Impressor'),
                        ),
                        OutlinedButton(
                          onPressed: () => applyPreset(
                            systemPermissions.map((item) => item.key).toSet(),
                          ),
                          child: const Text('Selecionar tudo'),
                        ),
                        TextButton(
                          onPressed: () => applyPreset({}),
                          child: const Text('Limpar'),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: active,
                            onChanged: (value) =>
                                setDialogState(() => active = value),
                          ),
                          Text(active ? 'Ativo' : 'Bloqueado'),
                        ],
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView(
                        children: _buildPermissionGroups(
                          selectedPermissions,
                          setDialogState,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  if (selectedPermissions.isEmpty) {
                    _message(
                      'Selecione pelo menos uma função para o usuário.',
                      error: true,
                    );
                    return;
                  }
                  try {
                    final updated = SystemUserModel(
                      id: user?.id,
                      authUserId: user?.authUserId,
                      username: usernameController.text.trim(),
                      fullName: nameController.text.trim(),
                      email: emailController.text.trim(),
                      password: user == null ? passwordController.text : '',
                      active: active,
                      permissions: selectedPermissions,
                    );
                    if (user == null) {
                      await _repository.create(updated);
                    } else {
                      await _repository.update(
                        updated,
                        newPassword: passwordController.text,
                      );
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  } on SupabaseException catch (error) {
                    _message(error.message, error: true);
                  } catch (e) {
                    _message(
                      'Não foi possível salvar. Verifique se o usuário já existe.',
                      error: true,
                    );
                  }
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar usuário'),
              ),
            ],
          );
        },
      ),
    );

    final saved = await navigator.push(route);
    await route.completed;
    nameController.dispose();
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    if (saved == true && mounted) {
      await _loadUsers();
      if (mounted) _message('Usuário e permissões salvos.');
    }
  }

  Future<void> _openAdminPasswordEditor(SystemUserModel admin) async {
    final formKey = GlobalKey<FormState>();
    final passwordController = TextEditingController();
    final confirmationController = TextEditingController();
    var obscurePassword = true;

    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<bool>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.admin_panel_settings, color: Color(0xFF0F62AC)),
              SizedBox(width: 10),
              Text('Alterar senha do administrador'),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: passwordController,
                    autofocus: true,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Nova senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setDialogState(
                          () => obscurePassword = !obscurePassword,
                        ),
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) => value == null ||
                            value.length < (_usesSupabase ? 6 : 4)
                        ? 'Use pelo menos ${_usesSupabase ? 6 : 4} caracteres'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmationController,
                    obscureText: obscurePassword,
                    decoration: const InputDecoration(
                      labelText: 'Confirmar nova senha',
                      prefixIcon: Icon(Icons.lock_reset),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value != passwordController.text
                        ? 'As senhas nao conferem'
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await _repository.updateAdminPassword(
                    admin,
                    passwordController.text,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } on SupabaseException catch (error) {
                  _message(error.message, error: true);
                } catch (e) {
                  _message('Nao foi possivel alterar a senha.', error: true);
                }
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar nova senha'),
            ),
          ],
        ),
      ),
    );

    final saved = await navigator.push(route);
    await route.completed;
    passwordController.dispose();
    confirmationController.dispose();
    if (saved == true && mounted) {
      _message('Senha do administrador alterada com sucesso.');
    }
  }

  List<Widget> _buildPermissionGroups(
    Set<String> selected,
    StateSetter setDialogState,
  ) {
    final groups = <String, List<SystemPermission>>{};
    for (final permission in systemPermissions) {
      groups.putIfAbsent(permission.group, () => []).add(permission);
    }
    return groups.entries.map((group) {
      return ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          group.key,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        children: group.value.map((permission) {
          return CheckboxListTile(
            dense: true,
            secondary: Icon(permission.icon, size: 20),
            title: Text(permission.label),
            value: selected.contains(permission.key),
            onChanged: (checked) {
              setDialogState(() {
                if (checked ?? false) {
                  selected.add(permission.key);
                } else {
                  selected.remove(permission.key);
                }
              });
            },
          );
        }).toList(),
      );
    }).toList();
  }

  Future<void> _deleteUser(SystemUserModel user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir usuário?'),
        content: Text('O usuário “${user.fullName}” não poderá mais entrar.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.delete(user);
      await _loadUsers();
    } on SupabaseException catch (error) {
      _message(error.message, error: true);
    } catch (e) {
      _message(e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        color: widget.isDark ? const Color(0xFF2D2D2D) : Colors.white,
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.admin_panel_settings,
                      color: Color(0xFF0F62AC)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Usuários e permissões',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: widget.isDark ? Colors.white : null,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _openUserEditor,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Novo usuário'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Escolha exatamente quais áreas cada funcionário poderá abrir.',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.isDark ? Colors.white70 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else
                ..._users.map(
                  (user) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          user.active ? const Color(0xFF0F62AC) : Colors.grey,
                      child: Text(
                        user.fullName.isEmpty
                            ? '?'
                            : user.fullName.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(
                      user.fullName,
                      style: TextStyle(
                        color: widget.isDark ? Colors.white : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      user.isAdmin
                          ? '@${user.username} • Administrador • Acesso total'
                          : '@${user.username} • ${user.permissions.length} função(ões)${user.active ? '' : ' • BLOQUEADO'}',
                      style: TextStyle(
                        color: widget.isDark ? Colors.white70 : null,
                      ),
                    ),
                    trailing: user.isAdmin
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Chip(label: Text('Protegido')),
                              IconButton(
                                onPressed: () => _openUserEditor(user: user),
                                icon: const Icon(Icons.lock_reset_outlined),
                                tooltip: 'Alterar senha do administrador',
                              ),
                            ],
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => _openUserEditor(user: user),
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Editar acessos',
                              ),
                              IconButton(
                                onPressed: () => _deleteUser(user),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                tooltip: 'Excluir usuário',
                              ),
                            ],
                          ),
                  ),
                ),
            ],
          ),
        ),
      );
}
