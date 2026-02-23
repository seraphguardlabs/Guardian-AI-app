import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/child.dart';
import '../utils/preferences_manager.dart';
import '../utils/app_theme.dart';
import '../services/api_service.dart';

class ProfileSelectionScreen extends StatefulWidget {
  final List<Child>? children;
  
  const ProfileSelectionScreen({super.key, this.children});

  @override
  State<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen> {
  late List<Child> _childrenList;
  final ApiService _apiService = ApiService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _childrenList = widget.children ?? [];
    debugPrint('📱 ProfileSelectionScreen initialized with ${_childrenList.length} children');
    
    // Auto-load children if list is empty
    if (_childrenList.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reloadChildren();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Try to get children from route arguments if not provided via constructor
    if (_childrenList.isEmpty) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is List<Child>) {
        _childrenList = args;
        debugPrint('📱 Children loaded from route arguments: ${_childrenList.length}');
      }
    }
  }

  Future<void> _reloadChildren() async {
    debugPrint('🔄 ProfileSelectionScreen: Reloading children list...');
    setState(() => _isLoading = true);
    
    try {
      final prefs = Provider.of<PreferencesManager>(context, listen: false);
      final email = prefs.getParentEmail() ?? '';
      final password = prefs.getParentPassword() ?? '';
      
      debugPrint('📤 ProfileSelectionScreen: Fetching children for email: $email');
      debugPrint('📤 ProfileSelectionScreen: Password available: ${password.isNotEmpty}');
      
      final result = await _apiService.fetchChildren(email, password);
      
      debugPrint('📥 ProfileSelectionScreen: Fetch children result success: ${result['success']}');
      debugPrint('📥 ProfileSelectionScreen: Children in result: ${result['children']}');
      
      if (result['success'] == true && result['children'] != null) {
        // fetchChildren already returns List<Child>, not raw JSON
        final childrenData = result['children'] as List<Child>;
        setState(() {
          _childrenList = childrenData;
        });
        debugPrint('✅ ProfileSelectionScreen: Children reloaded successfully: ${_childrenList.length} children');
        for (var child in _childrenList) {
          debugPrint('   - ${child.firstName} ${child.lastName} (${child.childHash})');
        }
      } else {
        debugPrint('❌ ProfileSelectionScreen: Failed to reload children: ${result['error']}');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ ProfileSelectionScreen: Error reloading children: $e');
      debugPrint('❌ ProfileSelectionScreen: Stack trace: $stackTrace');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: AnimatedGradientBg(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                const SizedBox(height: 80),
                
                // Logo and Title
                FadeSlideIn(
                  delay: const Duration(milliseconds: 0),
                  duration: const Duration(milliseconds: 600),
                  beginOffset: const Offset(0, -0.3),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: AppTheme.blueGrad,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: Colors.white,
                      size: 64,
                    ),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                FadeSlideIn(
                  delay: const Duration(milliseconds: 180),
                  child: const Text(
                    'Welcome to the Guardian AI',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                FadeSlideIn(
                  delay: const Duration(milliseconds: 300),
                  child: const Text(
                    'Empowering your child\'s journey\ntoday for a successful tomorrow',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),
                
                const Spacer(),
                
                // Parent Button
                FadeSlideIn(
                  delay: const Duration(milliseconds: 450),
                  beginOffset: const Offset(0, 0.5),
                  child: TapBounce(
                    onTap: () {
                      Navigator.pushReplacementNamed(context, '/parent_dashboard');
                    },
                    child: Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: AppTheme.blueGrad,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Parent',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Child Button
                FadeSlideIn(
                  delay: const Duration(milliseconds: 570),
                  beginOffset: const Offset(0, 0.5),
                  child: TapBounce(
                    onTap: _isLoading ? null : () {
                      debugPrint('👆 Child button pressed. Children count: ${_childrenList.length}');
                      if (_childrenList.isNotEmpty) {
                        if (_childrenList.length == 1) {
                          debugPrint('   Single child found, auto-selecting...');
                          _selectChild(_childrenList[0]);
                        } else {
                          debugPrint('   Multiple children found, showing dialog...');
                          _showChildSelectionDialog();
                        }
                      } else {
                        debugPrint('   No children found, showing add child dialog...');
                        _showAddChildDialog();
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                      ),
                      alignment: Alignment.center,
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Child',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectChild(Child child) async {
    debugPrint('👤 Selecting child: ${child.firstName} ${child.lastName}');
    final prefs = Provider.of<PreferencesManager>(context, listen: false);
    
    // Save selected child
    await prefs.setChildHash(child.childHash);
    await prefs.setChildName(child.firstName);
    debugPrint('✅ Child selected and saved to preferences');

    if (mounted) {
      // Navigate to Child Screen
      Navigator.pushReplacementNamed(context, '/child');
    }
  }

  void _showChildSelectionDialog() {
    debugPrint('📋 Showing child selection dialog with ${_childrenList.length} children');
    showDialog(
      context: context,
      builder: (dialogContext) {
        final maxHeight = MediaQuery.of(context).size.height * 0.7;
        return Dialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: maxHeight,
              maxWidth: 400,
            ),
            child: SingleChildScrollView(
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
                    ..._childrenList.map((child) => Padding(
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
                          debugPrint('👆 Child tile tapped: ${child.firstName}');
                          Navigator.pop(dialogContext);
                          _selectChild(child);
                        },
                      ),
                    )),
                    const SizedBox(height: 8),
                    // Add Child Option
                    ListTile(
                      tileColor: const Color(0xFF2B4C8F).withOpacity(0.3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFF2B4C8F),
                        child: Icon(Icons.add, color: Colors.white),
                      ),
                      title: const Text(
                        'Add New Child',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
                      onTap: () {
                        debugPrint('👆 Add New Child tapped');
                        Navigator.pop(dialogContext);
                        _showAddChildDialog();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAddChildDialog() {
    debugPrint('📝 Showing Add Child dialog');
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final dateOfBirthController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        final maxHeight = MediaQuery.of(context).size.height * 0.8;
        return Dialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: maxHeight,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Add Child',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // First Name Field
                      TextFormField(
                        controller: firstNameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'First Name',
                          labelStyle: const TextStyle(color: Colors.white54),
                          prefixIcon: const Icon(Icons.person_outline, color: Colors.white54),
                          filled: true,
                          fillColor: const Color(0xFF0F0F0F),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF2B4C8F), width: 2),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter first name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Last Name Field
                      TextFormField(
                        controller: lastNameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Last Name',
                          labelStyle: const TextStyle(color: Colors.white54),
                          prefixIcon: const Icon(Icons.person, color: Colors.white54),
                          filled: true,
                          fillColor: const Color(0xFF0F0F0F),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF2B4C8F), width: 2),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter last name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Date of Birth Field
                      TextFormField(
                        controller: dateOfBirthController,
                        style: const TextStyle(color: Colors.white),
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Date of Birth',
                          labelStyle: const TextStyle(color: Colors.white54),
                          prefixIcon: const Icon(Icons.calendar_today, color: Colors.white54),
                          filled: true,
                          fillColor: const Color(0xFF0F0F0F),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF2B4C8F), width: 2),
                          ),
                        ),
                        onTap: () async {
                          debugPrint('📅 Date picker tapped');
                          final DateTime? picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                            builder: (context, child) {
                              return Theme(
                                data: ThemeData.dark().copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: Color(0xFF2B4C8F),
                                    onPrimary: Colors.white,
                                    surface: Color(0xFF1A1A1A),
                                    onSurface: Colors.white,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            dateOfBirthController.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                            debugPrint('📅 Date selected: ${dateOfBirthController.text}');
                          }
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please select date of birth';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () async {
                          debugPrint('👆 Add Child button pressed');
                          if (formKey.currentState!.validate()) {
                            debugPrint('✅ Form validated');
                            Navigator.pop(dialogContext);
                            
                            // Show loading
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Row(
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Adding child...'),
                                  ],
                                ),
                                backgroundColor: Color(0xFF2B4C8F),
                                duration: Duration(seconds: 10),
                              ),
                            );

                            // Get credentials from preferences
                            final prefs = Provider.of<PreferencesManager>(context, listen: false);
                            final email = prefs.getParentEmail() ?? '';
                            final password = prefs.getParentPassword() ?? '';
                            
                            debugPrint('📤 Adding child with credentials:');
                            debugPrint('   Email: $email');
                            debugPrint('   First Name: ${firstNameController.text.trim()}');
                            debugPrint('   Last Name: ${lastNameController.text.trim()}');
                            debugPrint('   DOB: ${dateOfBirthController.text.trim()}');

                            // Call API
                            final result = await _apiService.addChild(
                              email,
                              password,
                              firstNameController.text.trim(),
                              lastNameController.text.trim(),
                              dateOfBirthController.text.trim(),
                            );

                            debugPrint('📥 Add child API result: $result');
                            
                            // Hide loading snackbar
                            if (mounted) {
                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            }

                            if (result['success'] == true && mounted) {
                              debugPrint('✅ Child added successfully!');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(result['message'] ?? 'Child added successfully!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              
                              // Reload children list
                              await _reloadChildren();
                              
                              // Show the updated child selection dialog
                              if (mounted && _childrenList.isNotEmpty) {
                                _showChildSelectionDialog();
                              }
                            } else if (mounted) {
                              debugPrint('❌ Failed to add child: ${result['error']}');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(result['error'] ?? 'Failed to add child'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } else {
                            debugPrint('❌ Form validation failed');
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2B4C8F),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Add Child',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          debugPrint('👆 Cancel button pressed');
                          Navigator.pop(dialogContext);
                        },
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
