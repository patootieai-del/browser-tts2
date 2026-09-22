import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/bookmarks_screen.dart';
import '../screens/history_screen.dart';
import '../screens/reader_screen.dart';
import '../screens/settings_screen.dart';
import '../state/tabs_controller.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  Future<void> _openAndLoad(BuildContext context, Widget page) async {
    final tabs = context.read<TabsController>();
    final url = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => page));
    if (url != null) await tabs.load(url); // no BuildContext used after await
  }

  @override
  Widget build(BuildContext context) {
    final tabs = context.read<TabsController>();
    return Drawer(
      child: SafeArea(
        child: ListView(children: [
          const DrawerHeader(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text('Vox Browser',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('New tab'),
            onTap: () {
              Navigator.pop(context);
              tabs.newTab();
            },
          ),
          ListTile(
            leading: const Icon(Icons.visibility_off),
            title: const Text('New incognito tab'),
            onTap: () {
              Navigator.pop(context);
              tabs.newTab(incognito: true);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.chrome_reader_mode),
            title: const Text('Reader view'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ReaderScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.star_border),
            title: const Text('Bookmarks'),
            onTap: () {
              Navigator.pop(context);
              _openAndLoad(context, const BookmarksScreen());
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('History'),
            onTap: () {
              Navigator.pop(context);
              _openAndLoad(context, const HistoryScreen());
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
        ]),
      ),
    );
  }
}