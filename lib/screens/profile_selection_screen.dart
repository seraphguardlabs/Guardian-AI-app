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
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              const SizedBox(height: 80),
              
              // Logo and Title
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF2B4C8F),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: Colors.white,
                  size: 64,
                ),
              ),
              
              const SizedBox(height: 32),
              
              const Text(
                'Welcome to the Guardian AI',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 12),
              
              const Text(
                'Empowering your child\'s journey\ntoday for a successful tomorrow',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              
              const Spacer(),
              
              // Parent Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(context, '/parent_dashboard');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2B4C8F),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Parent',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Child Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    if (childrenList.isNotEmpty) {
                      // If there's only one child, select it automatically
                      if (childrenList.length == 1) {
                        _selectChild(context, childrenList[0]);
                      } else {
                        // Show child selection dialog
                        _showChildSelectionDialog(context, childrenList);
                      }
                    } else {
                      // Show message if no children found
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No child profiles found. Please create a profile on the web dashboard.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFF2B2B2B), width: 1),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Child',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 60),
            ],
          ),
        ),
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

  void _showChildSelectionDialog(BuildContext context, List<Child> children) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select Child Profile',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              ...children.map((child) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  tileColor: const Color(0xFF2B2B2B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF2B4C8F),
                    backgroundImage: child.profileImageUrl != null
                        ? NetworkImage(child.profileImageUrl!)
                        : null,
                    child: child.profileImageUrl == null
                        ? Text(
                            child.firstName[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  title: Text(
                    '${child.firstName} ${child.lastName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
                  onTap: () {
                    Navigator.pop(context);
                    _selectChild(context, child);
                  },
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}
