import 'package:flutter/material.dart';

import '../parties/banks_screen.dart';
import '../parties/parties_screen.dart';
import '../projects/projects_screen.dart';
import '../settings/material_types_screen.dart';
import 'labour_types_screen.dart';

/// "Manage" tab — landing page that gathers the four entity-management
/// screens (Materials, Wallets/Banks, Suppliers, Projects) under a single
/// bottom-nav destination so the four bottom slots can be: Home · Settings
/// · Reports · Manage.
///
/// Each card pushes onto the navigator so the user gets a normal back stack
/// — keeping the host scaffolds (which carry their own AppBars + FABs)
/// untouched.
class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _ManageCard(
            icon: Icons.foundation,
            title: 'Projects',
            subtitle: 'Active sites, archived jobs and project metadata',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProjectsScreen()),
            ),
          ),
          _ManageCard(
            icon: Icons.local_shipping,
            title: 'Suppliers',
            subtitle: 'Material vendors and labour providers',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SuppliersScreen()),
            ),
          ),
          _ManageCard(
            icon: Icons.account_balance,
            title: 'Wallets & Banks',
            subtitle:
                'Cash accounts, supervisor floats and bank/wallet ledgers',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BanksScreen()),
            ),
          ),
          _ManageCard(
            icon: Icons.category,
            title: 'Material Types',
            subtitle:
                'Categories shown in the Buy Material dropdown (Brick, Cement, custom…)',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MaterialTypesScreen()),
            ),
          ),
          _ManageCard(
            icon: Icons.engineering,
            title: 'Labour Types',
            subtitle:
                'Skill categories for labour (Mason, Electrician, Plumber…)',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LabourTypesScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManageCard extends StatelessWidget {
  const _ManageCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
