import 'package:flutter/material.dart';

import '../models/chapter_rule.dart';
import '../state/chapter_rule_store.dart';
import '../state/element_picker_controller.dart';

Future<void> showChapterRuleSheet(
  BuildContext context, {
  required ElementPickerController picker,
  required ChapterRuleStore rules,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RuleSheet(picker: picker, rules: rules),
  );
  await picker.stop();
}

class _RuleSheet extends StatefulWidget {
  const _RuleSheet({required this.picker, required this.rules});
  final ElementPickerController picker;
  final ChapterRuleStore rules;
  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  late final TextEditingController _prefix;
  String? _error;

  @override
  void initState() {
    super.initState();
    final url = widget.picker.picked?.url ?? '';
    _prefix = TextEditingController(text: PrefixSuggestions.of(url).folder);
  }

  @override
  void dispose() {
    _prefix.dispose();
    super.dispose();
  }

  Future<void> _save(PickedElement p) async {
    final prefix = _prefix.text.trim();
    if (prefix.isEmpty || !p.url.toLowerCase().startsWith(prefix.toLowerCase())) {
      setState(() => _error = 'The prefix must match this page\'s URL.');
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    await widget.rules.upsert(ChapterRule(
        urlPrefix: prefix, selector: p.selector, label: p.label));
    nav.pop();
    messenger?.showSnackBar(SnackBar(
        content: Text('Saved. Auto-read will press this button on pages starting with $prefix')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.picker,
      builder: (context, _) {
        final p = widget.picker.picked;
        if (p == null) return const SizedBox(height: 120);
        final sugg = PrefixSuggestions.of(p.url);

        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Use this as the "next chapter" button?',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.label.isEmpty ? '<${p.tag}>' : '"${p.label}"  <${p.tag}>',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(p.selector,
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: cs.onSurfaceVariant)),
                  ]),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: p.canGoUp ? widget.picker.up : null,
                    icon: const Icon(Icons.north),
                    label: const Text('Select parent element'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _prefix,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: 'Apply when the URL starts with',
                    errorText: _error,
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  ActionChip(
                      label: const Text('Whole site'),
                      onPressed: () => setState(() => _prefix.text = sugg.site)),
                  ActionChip(
                      label: const Text('This folder'),
                      onPressed: () => setState(() => _prefix.text = sugg.folder)),
                  ActionChip(
                      label: const Text('This page only'),
                      onPressed: () => setState(() => _prefix.text = sugg.exact)),
                ]),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: () => _save(p), child: const Text('Save')),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}