import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/child.dart';
import '../utils/preferences_manager.dart';

class ProfileSelectionScreen extends StatelessWidget {
  final List<Child>? children;
  
  const ProfileSelectionScreen({super.key, this.children});

  @override
  Widget build(BuildContext context) {
    // Try to get children from constructor first, then from route arguments
    final List<Child> childrenList = children ?? 
        (ModalRoute.of(context)?.settings.arguments as List<Child>? ?? []);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text('Select Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Parent Dashboard Option
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF5B4A9F), Color(0xFF4A3280)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF5B4A9F).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.pushReplacementNamed(context, '/parent_dashboard');
                },
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.admin_panel_settings,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Parent Dashboard',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Monitor your children\'s activity',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // Divider with text
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Expanded(child: Divider(color: Colors.white24)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR SELECT CHILD PROFILE',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: Colors.white24)),
              ],
            ),
          ),
          
          // Child profiles list
          Expanded(
            child: childrenList.isEmpty
                ? const Center(
                    child: Text(
                      'No child profiles found.\nPlease create a profile on the web dashboard.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.white60),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: childrenList.length,
                    itemBuilder: (context, index) {
                      final child = childrenList[index];
                      return Card(
                        color: const Color(0xFF1A1A1A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            radius: 30,
                            backgroundColor: Color(0xFF5B4A9F).withOpacity(0.3),
                            backgroundImage: child.profileImageUrl != null
                                ? NetworkImage(child.profileImageUrl!)
                                : null,
                            child: child.profileImageUrl == null
                                ? Text(
                                    child.firstName[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF9C27B0),
                                    ),
                                  )
                                : null,
                          ),
                          title: Text(
                            '${child.firstName} ${child.lastName}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          subtitle: const Text('Tap to monitor this device', style: TextStyle(color: Colors.white60)),
                          trailing: const Icon(Icons.arrow_forward_ios, color: Color(0xFF9C27B0)),
                          onTap: () async {
                            await _selectChild(context, child);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectChild(BuildContext context, Child child) async {
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    
    // Save selected child
    await prefs.setChildHash(child.childHash);
    await prefs.setChildName(child.firstName);

    if (context.mounted) {
      // Navigate to Child Screen
      Navigator.pushReplacementNamed(context, '/child');
    }
  }
}
