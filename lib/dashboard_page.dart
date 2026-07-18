import 'package:flutter/material.dart';

class DashboardPage extends StatelessWidget {
  final List<Map<String, dynamic>> tasks;

  const DashboardPage({super.key, required this.tasks});

  @override
  Widget build(BuildContext context) {
    final total = tasks.length;
    final completed = tasks.where((t) => t['done'] == true).length;
    final pending = total - completed;
    final highPriority = tasks.where((t) => t['priority'] == 'High').length;
    final autoCreated = tasks.where((t) => t['autoCreated'] == true).length;
    final progress = total == 0 ? 0.0 : completed / total;

    Widget buildCard(String title, String value, IconData icon) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          trailing: Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      '${(progress * 100).toInt()}% Completed',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            buildCard('Total Tasks', total.toString(), Icons.list),
            buildCard('Completed', completed.toString(), Icons.check_circle),
            buildCard('Pending', pending.toString(), Icons.pending),
            buildCard(
              'High Priority',
              highPriority.toString(),
              Icons.priority_high,
            ),
            buildCard(
              'Auto Created',
              autoCreated.toString(),
              Icons.auto_awesome,
            ),
          ],
        ),
      ),
    );
  }
}
