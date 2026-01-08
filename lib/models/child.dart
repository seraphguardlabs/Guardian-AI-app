/// Child model representing a child's profile
/// 
/// Used throughout the app to identify and display child information.
/// The childHash is the primary identifier used in API calls.
/// 
/// Example usage:
/// ```dart
/// final child = Child.fromJson(jsonData);
/// ApiService().getScreenTime(child.childHash);
/// ```
class Child {
  /// Unique identifier for the child (SHA-256 hash)
  /// Used in all API endpoints: /api/mobile/child/<hash>/...
  final String childHash;
  
  /// Child's first name for display purposes
  final String firstName;
  
  /// Child's last name for display purposes
  final String lastName;
  
  /// Optional profile image URL
  /// Null if no profile picture uploaded
  final String? profileImageUrl;

  Child({
    required this.childHash,
    required this.firstName,
    required this.lastName,
    this.profileImageUrl,
  });

  /// Create Child instance from JSON API response
  factory Child.fromJson(Map<String, dynamic> json) {
    return Child(
      childHash: json['child_hash'] ?? '',
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      profileImageUrl: json['profile_image_url'],
    );
  }

  /// Convert Child instance to JSON for API requests
  Map<String, dynamic> toJson() {
    return {
      'child_hash': childHash,
      'first_name': firstName,
      'last_name': lastName,
      'profile_image_url': profileImageUrl,
    };
  }
  
  /// Get full display name
  String get fullName => '$firstName $lastName';
  
  /// Get initials for avatar fallback (e.g., "JD" for John Doe)
  String get initials => 
      firstName.isNotEmpty && lastName.isNotEmpty
          ? '${firstName[0]}${lastName[0]}'.toUpperCase()
          : '??';
}

