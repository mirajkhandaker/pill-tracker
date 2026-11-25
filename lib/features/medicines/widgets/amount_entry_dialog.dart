import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Prompts for a numeric dose amount (variable-dose or PRN logging).
/// Resolves to the entered amount, or null if cancelled.
Future<double?> showAmountEntryDialog(
  BuildContext context, {
  required String title,
  required String unitLabel,
  double? initial,
}) {
  return showDialog<double>(
    context: context,
    builder: (context) => _AmountEntryDialog(
      title: title,
      unitLabel: unitLabel,
      initial: initial,
    ),
  );
}

class _AmountEntryDialog extends StatefulWidget {
  const _AmountEntryDialog({
    required this.title,
    required this.unitLabel,
    this.initial,
  });

  final String title;
  final String unitLabel;
  final double? initial;

  @override
  State<_AmountEntryDialog> createState() => _AmountEntryDialogState();
}

class _AmountEntryDialogState extends State<_AmountEntryDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial == null ? '' : _trim(widget.initial!),
    );
  }

  static String _trim(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter an amount greater than 0');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: InputDecoration(
          labelText: 'Amount',
          suffixText: widget.unitLabel,
          errorText: _error,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
