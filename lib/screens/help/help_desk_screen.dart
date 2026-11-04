import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpDeskScreen extends StatefulWidget {
  const HelpDeskScreen({super.key});

  @override
  State<HelpDeskScreen> createState() => _HelpDeskScreenState();
}

class _HelpDeskScreenState extends State<HelpDeskScreen> {
  // Dados de contato
  final String _phoneNumber = '15981049471';
  final String _email = 'suportemastersystem@gmail.com';
  final String _whatsappNumber = '15981049471';
  final String _website = 'mastersystem.com.br';

  // Lista de FAQs
  final List<Map<String, String>> _faqs = [
    {
      'pergunta': 'Como criar uma nova Ordem de Serviço?',
      'resposta':
          'Acesse o módulo Vendas/Orçamento, selecione um cliente, adicione os produtos e clique em "Gravar e Imprimir".',
    },
    {
      'pergunta': 'Como aprovar um orçamento?',
      'resposta':
          'Vá em Orçamentos Pendentes, localize o orçamento desejado e clique em "Aprovar".',
    },
    {
      'pergunta': 'Como faço backup do sistema?',
      'resposta':
          'Acesse o módulo Backup, clique em "Executar Backup" e aguarde a conclusão.',
    },
    {
      'pergunta': 'Como importar uma Nota Fiscal (XML)?',
      'resposta':
          'No módulo Arquivo, selecione "Importar Nota Fiscal (XML)" e escolha o arquivo.',
    },
    {
      'pergunta': 'Como alterar o status de um pedido na produção?',
      'resposta':
          'No módulo Produção, clique no pedido, use os botões "Avançar" ou "Voltar" para alterar o status.',
    },
  ];

  String _searchFaq = '';

  List<Map<String, String>> get _filteredFaqs {
    if (_searchFaq.isEmpty) return _faqs;
    return _faqs.where((faq) {
      final search = _searchFaq.toLowerCase();
      return faq['pergunta']!.toLowerCase().contains(search) ||
          faq['resposta']!.toLowerCase().contains(search);
    }).toList();
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        throw Exception('Não foi possível abrir o telefone');
      }
    } catch (e) {
      _showError('Erro ao fazer ligação: $e');
    }
  }

  Future<void> _sendEmail(String email) async {
    final Uri launchUri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=CHAMADO TÉCNICO - MatterdiSistem',
    );
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        throw Exception('Não foi possível abrir o e-mail');
      }
    } catch (e) {
      _showError('Erro ao abrir e-mail: $e');
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    final Uri launchUri = Uri(
      scheme: 'https',
      host: 'wa.me',
      path: '55$phone',
    );
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        throw Exception('Não foi possível abrir o WhatsApp');
      }
    } catch (e) {
      _showError('Erro ao abrir WhatsApp: $e');
    }
  }

  Future<void> _openWebsite(String url) async {
    final Uri launchUri = Uri(scheme: 'https', host: url);
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        throw Exception('Não foi possível abrir o site');
      }
    } catch (e) {
      _showError('Erro ao abrir site: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showFaqDetail(Map<String, String> faq) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Row(
          children: [
            const Icon(Icons.help_outline, color: Color(0xFF0F62AC)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                faq['pergunta']!,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          faq['resposta']!,
          style: const TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _openTicketForm() {
    showDialog(
      context: context,
      builder: (context) {
        final formKey = GlobalKey<FormState>();
        final nameController = TextEditingController();
        final emailController = TextEditingController();
        final subjectController = TextEditingController();
        final messageController = TextEditingController();

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F62AC).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.assignment, color: Color(0xFF0F62AC)),
              ),
              const SizedBox(width: 12),
              const Text('Abrir Chamado'),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Seu Nome *',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Seu E-mail *',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: subjectController,
                    decoration: const InputDecoration(
                      labelText: 'Assunto *',
                      prefixIcon: Icon(Icons.subject),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: messageController,
                    decoration: const InputDecoration(
                      labelText: 'Mensagem *',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                    validator: (v) => v!.isEmpty ? 'Campo obrigatório' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context);
                  final subject = 'CHAMADO TÉCNICO - ${subjectController.text}';
                  final body = '''
Nome: ${nameController.text}
E-mail: ${emailController.text}
Assunto: ${subjectController.text}

Mensagem:
${messageController.text}
                  '''
                      .trim();

                  final Uri emailUri = Uri(
                    scheme: 'mailto',
                    path: _email,
                    query: 'subject=$subject&body=${Uri.encodeComponent(body)}',
                  );

                  try {
                    if (await canLaunchUrl(emailUri)) {
                      await launchUrl(emailUri);
                      _showSuccess('Chamado aberto com sucesso!');
                    } else {
                      throw Exception('Não foi possível abrir o e-mail');
                    }
                  } catch (e) {
                    _showError('Erro ao abrir chamado: $e');
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F62AC),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: const Text('Enviar Chamado'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Cabeçalho
          Row(
            children: [
              const Icon(Icons.support_agent,
                  color: Color(0xFF0F62AC), size: 28),
              const SizedBox(width: 12),
              Text(
                'Suporte Técnico',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ========== CONTATOS ==========
          Text(
            'Contatos',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),

          // Telefone
          _buildContactCard(
            'Telefone',
            Icons.phone,
            '(15) 98104-9471',
            'Seg-Sex 8h às 18h',
            Colors.blue,
            () => _makePhoneCall(_phoneNumber),
            'Ligar',
          ),
          const SizedBox(height: 12),

          // WhatsApp
          _buildContactCard(
            'WhatsApp',
            Icons.chat,
            '(15) 98104-9471',
            'Atendimento rápido via mensagem',
            Colors.green,
            () => _openWhatsApp(_whatsappNumber),
            'Abrir Chat',
          ),
          const SizedBox(height: 12),

          // E-mail
          _buildContactCard(
            'E-mail',
            Icons.email,
            _email,
            'Resposta em até 24h úteis',
            Colors.red,
            () => _sendEmail(_email),
            'Enviar E-mail',
          ),
          const SizedBox(height: 12),

          // Site
          _buildContactCard(
            'Site Oficial',
            Icons.public,
            _website,
            'Acesse nosso site para mais informações',
            Colors.purple,
            () => _openWebsite(_website),
            'Acessar Site',
          ),
          const SizedBox(height: 16),

          // ========== CHAMADO ==========
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.assignment,
                            color: Colors.purple, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Abrir Chamado Técnico',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Preencha o formulário e envie seu chamado diretamente para nossa equipe de suporte.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openTicketForm,
                      icon: const Icon(Icons.send, size: 16),
                      label: const Text('Abrir Chamado'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ========== FAQ ==========
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFE0E0E0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.help,
                            color: Colors.orange, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Perguntas Frequentes (FAQ)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Campo de busca
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar na FAQ...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    onChanged: (value) {
                      setState(() => _searchFaq = value);
                    },
                  ),
                  const SizedBox(height: 12),

                  // Lista de FAQs
                  _filteredFaqs.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Nenhuma pergunta encontrada',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _filteredFaqs.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final faq = _filteredFaqs[index];
                            return ListTile(
                              leading: const Icon(
                                Icons.help_outline,
                                color: Color(0xFF0F62AC),
                                size: 20,
                              ),
                              title: Text(
                                faq['pergunta']!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: Colors.grey,
                              ),
                              onTap: () => _showFaqDetail(faq),
                            );
                          },
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ========== RODAPÉ ==========
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey),
                    SizedBox(width: 8),
                    Text(
                      'Horário de Atendimento:',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Seg-Sex 8h às 18h',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F62AC),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Tempo médio de resposta: 24h úteis',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildContactCard(
    String title,
    IconData icon,
    String value,
    String subtitle,
    Color color,
    VoidCallback onPressed,
    String buttonText,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 13,
                          color: color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onPressed,
                icon: Icon(
                  buttonText == 'Ligar'
                      ? Icons.phone
                      : buttonText == 'Abrir Chat'
                          ? Icons.chat
                          : buttonText == 'Enviar E-mail'
                              ? Icons.email
                              : buttonText == 'Acessar Site'
                                  ? Icons.public
                                  : Icons.send,
                  size: 16,
                ),
                label: Text(buttonText),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
