import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/finance_calculations.dart';

class FinanceField {
  const FinanceField(this.key, this.label,
      {this.kind = 'text',
      this.required = false,
      this.options = const {},
      this.minimum,
      this.maximum,
      this.hint});
  final String key, label, kind;
  final bool required;
  final Map<String, String> options;
  final double? minimum, maximum;
  final String? hint;
}

class FinanceFormDialog extends StatefulWidget {
  const FinanceFormDialog(
      {super.key,
      required this.title,
      required this.fields,
      this.initial = const {},
      this.description});
  final String title;
  final List<FinanceField> fields;
  final Map<String, dynamic> initial;
  final String? description;
  @override
  State<FinanceFormDialog> createState() => _FinanceFormDialogState();
}

class _FinanceFormDialogState extends State<FinanceFormDialog> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, dynamic> _values = {};

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      final initial = widget.initial[field.key];
      if (field.kind == 'select') {
        _values[field.key] = initial?.toString() ??
            (field.required && field.options.isNotEmpty
                ? field.options.keys.first
                : null);
        if (!field.options.containsKey(_values[field.key]))
          _values[field.key] = null;
      } else if (field.kind == 'bool') {
        _values[field.key] = initial == true;
      } else if (field.kind == 'date') {
        _values[field.key] = initial == null
            ? (field.required ? DateTime.now() : null)
            : DateTime.tryParse(initial.toString());
      } else {
        _controllers[field.key] =
            TextEditingController(text: initial?.toString() ?? '');
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(FinanceField field) {
    final decoration = InputDecoration(
        labelText: '${field.label}${field.required ? ' *' : ''}',
        hintText: field.hint,
        border: const OutlineInputBorder());
    if (field.kind == 'select') {
      return DropdownButtonFormField<String>(
        initialValue: _values[field.key] as String?,
        decoration: decoration,
        isExpanded: true,
        items: [
          if (!field.required)
            const DropdownMenuItem(value: '', child: Text('Não informado')),
          ...field.options.entries.map((entry) => DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis)))
        ],
        validator: (value) => field.required && (value == null || value.isEmpty)
            ? 'Selecione uma opção.'
            : null,
        onChanged: (value) => _values[field.key] = value,
      );
    }
    if (field.kind == 'bool') {
      return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(field.label),
          value: _values[field.key] == true,
          onChanged: (value) => setState(() => _values[field.key] = value));
    }
    if (field.kind == 'date') {
      final date = _values[field.key] as DateTime?;
      return FormField<DateTime>(
        initialValue: date,
        validator: (_) => field.required && _values[field.key] == null
            ? 'Informe a data.'
            : null,
        builder: (state) => InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                  context: context,
                  initialDate: date ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100));
              if (picked != null) {
                setState(() => _values[field.key] = picked);
                state.didChange(picked);
              }
            },
            child: InputDecorator(
                decoration: decoration.copyWith(errorText: state.errorText),
                child: Row(children: [
                  Expanded(
                      child: Text(date == null
                          ? 'Selecionar data'
                          : DateFormat('dd/MM/yyyy').format(date))),
                  if (!field.required && date != null)
                    IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'Remover data',
                        onPressed: () {
                          setState(() => _values[field.key] = null);
                          state.didChange(null);
                        }),
                  const Icon(Icons.calendar_today, size: 18)
                ]))),
      );
    }
    final numeric = field.kind == 'money' ||
        field.kind == 'number' ||
        field.kind == 'integer';
    return TextFormField(
        controller: _controllers[field.key],
        decoration: decoration,
        maxLines: field.kind == 'multiline' ? 3 : 1,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : null,
        validator: (text) {
          if ((text ?? '').trim().isEmpty)
            return field.required ? 'Campo obrigatório.' : null;
          if (numeric) {
            final value = financeParseNumber(text!);
            if (value == null) return 'Informe um número válido.';
            if (field.kind == 'integer' && value != value.roundToDouble())
              return 'Informe um número inteiro.';
            if (field.minimum != null && value < field.minimum!)
              return 'Mínimo: ${field.minimum}.';
            if (field.maximum != null && value > field.maximum!)
              return 'Máximo: ${field.maximum}.';
          }
          return null;
        });
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final result = <String, dynamic>{};
    for (final field in widget.fields) {
      if (field.kind == 'date') {
        result[field.key] =
            (_values[field.key] as DateTime?)?.toIso8601String();
      } else if (field.kind == 'select' || field.kind == 'bool') {
        result[field.key] = _values[field.key];
      } else {
        final text = _controllers[field.key]!.text.trim();
        result[field.key] = switch (field.kind) {
          'integer' => financeParseNumber(text)?.toInt(),
          'money' || 'number' => financeParseNumber(text),
          _ => text,
        };
      }
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.title),
          content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                  child: Form(
                      key: _form,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.description != null)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Text(widget.description!)),
                            ...widget.fields.map((field) => Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _field(field)))
                          ])))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(onPressed: _submit, child: const Text('Salvar'))
          ]);
}
