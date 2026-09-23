import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chapter_rule.dart';
import '../state/chapter_rule_store.dart';

class ChapterRulesScreen extends StatelessWidget {
  const ChapterRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ChapterRuleStore>();
    final rules = store.rules;
    return Scaffold(
      appBar: AppBar(title: const Text('Next-chapter buttons')),
      body: rules.isEmpty
          ? const Center(
              child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'None saved yet.\nOpen a chapter, then use the ⋮ menu → '
                '"Set next-chapter button" and tap the Next button on the page.',
                textAlign: TextAlign.center,
              ),
            ))
          : ListView.separated(
              itemCount: rules.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final r = rules[i];
                return Dismissible(
                  key: ValueKey(r.urlPrefix),
                  background: Container(color: Colors.red),
                  onDismissed: (_) => store.remove(r.urlPrefix),
                  child: ListTile(
                    title: Text(r.urlPrefix,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${r.label.isEmpty ? 'element' : '"${r.label}"'} · ${r.selector}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Switch(
                      value: r.enabled,
                      onChanged: (v) => store.setEnabled(r.urlPrefix, v),
                    ),
                    onTap: () => _editPrefix(ctx, store, r),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _editPrefix(
      BuildContext context, ChapterRuleStore store, ChapterRule r) async {
    final ctrl = TextEditingController(text: r.urlPrefix);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('URL starts with'),
        content: TextField(
            controller: ctrl, autofocus: true, keyboardType: TextInputType.url),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    ctrl.dispose();
    if (v != null && v.isNotEmpty && v != r.urlPrefix) {
      await store.remove(r.urlPrefix);
      await store.upsert(r.copyWith(urlPrefix: v));
    }
  }
}
