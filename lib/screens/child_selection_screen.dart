import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/child.dart';
import '../utils/preferences_manager.dart';

class ChildSelectionScreen extends StatelessWidget {
  final List<Child>? children;
  
  const ChildSelectionScreen({super.key, this.children});

  @override
  Widget build(BuildContext context) {
    // Try to get children from constructor first, then from route arguments
    final List<Child> childrenList = children ?? 
        (ModalRoute.of(context)?.settings.arguments as List<Child>? ?? []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Child'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: childrenList.isEmpty
          ? const Center(
              child: Text(
                'No child profiles found.\nPlease create a profile on the web dashboard.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: childrenList.length,
              itemBuilder: (context, index) {
                final child = childrenList[index];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.blue.shade100,
                      backgroundImage: child.profileImageUrl != null
                          ? NetworkImage(child.profileImageUrl!)
                          : null,
                      child: child.profileImageUrl == null
                          ? Text(
                              child.firstName[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            )
                          : null,
                    ),
                    title: Text(
                      '${child.firstName} ${child.lastName}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text('Tap to monitor this device'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () async {
                      await _selectChild(context, child);
                    },
                  ),
                );
              },
            ),
    );
  }

  Future<void> _selectChild(BuildContext context, Child child) async {
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    
    // Save selected child
    await prefs.setChildHash(child.childHash);
    await prefs.setChildName(child.firstName);

    if (context.mounted) {
      // Navigate to Dashboard
      Navigator.pushReplacementNamed(context, '/dashboard');
    }
  }
}
