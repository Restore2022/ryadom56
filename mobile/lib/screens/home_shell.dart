import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'create_listing_screen.dart';

const categoryLabels = {
  'goods': 'Товары',
  'services': 'Услуги',
  'jobs': 'Работа',
  'rent': 'Аренда',
  'free': 'Отдам',
  'lost_found': 'Потеряшки',
  'school': 'Школа',
  'hospital': 'Больница',
  'shop': 'Магазин',
  'pharmacy': 'Аптека',
  'admin': 'Администрация',
  'bank': 'Банк',
  'post': 'Почта',
  'transport': 'Транспорт',
  'culture': 'Культура',
  'sport': 'Спорт',
  'other': 'Другое',
};

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pages = [
      _ListingsTab(items: state.listings),
      _DirectoryTab(items: state.directory),
      _ProfileTab(user: state.user),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Рядом56'),
        actions: [
          if (index == 0)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateListingScreen())),
            ),
        ],
      ),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront_outlined), label: 'Объявления'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'Справочник'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Профиль'),
        ],
      ),
    );
  }
}

class _ListingsTab extends StatelessWidget {
  const _ListingsTab({required this.items});
  final List<dynamic> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('Пока нет опубликованных объявлений'));
    }
    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().refreshPublic(),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final item = items[i] as Map<String, dynamic>;
          return Card(
            child: ListTile(
              title: Text(item['title'] as String),
              subtitle: Text(
                '${categoryLabels[item['category']] ?? item['category']} · ${item['settlement_name'] ?? ''}\n${item['description']}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              isThreeLine: true,
              trailing: item['price'] != null ? Text('${item['price']} ₽') : null,
            ),
          );
        },
      ),
    );
  }
}

class _DirectoryTab extends StatelessWidget {
  const _DirectoryTab({required this.items});
  final List<dynamic> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('Справочник пока пуст — добавьте записи в админке'));
    }
    return RefreshIndicator(
      onRefresh: () => context.read<AppState>().refreshPublic(),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final item = items[i] as Map<String, dynamic>;
          return Card(
            child: ListTile(
              title: Text(item['title'] as String),
              subtitle: Text(
                '${categoryLabels[item['category']] ?? item['category']}'
                '${item['settlement_name'] != null ? ' · ${item['settlement_name']}' : ''}'
                '${item['address'] != null ? '\n${item['address']}' : ''}'
                '${item['phone'] != null ? '\n${item['phone']}' : ''}',
              ),
              isThreeLine: true,
            ),
          );
        },
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.user});
  final Map<String, dynamic>? user;

  @override
  Widget build(BuildContext context) {
    if (user == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(user!['full_name'] as String, style: Theme.of(context).textTheme.headlineSmall),
        Text(user!['email'] as String),
        if (user!['phone'] != null) Text(user!['phone'] as String),
        const SizedBox(height: 8),
        Text('Роль: ${user!['role']}'),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () async {
            await context.read<AppState>().logout();
            if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
          },
          child: const Text('Выйти'),
        ),
      ],
    );
  }
}
