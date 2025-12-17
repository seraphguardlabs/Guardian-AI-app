class Child {
  final String childHash;
  final String firstName;
  final String lastName;
  final String? profileImageUrl;

  Child({
    required this.childHash,
    required this.firstName,
    required this.lastName,
    this.profileImageUrl,
  });

  factory Child.fromJson(Map<String, dynamic> json) {
    return Child(
      childHash: json['child_hash'] ?? '',
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      profileImageUrl: json['profile_image_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'child_hash': childHash,
      'first_name': firstName,
      'last_name': lastName,
      'profile_image_url': profileImageUrl,
    };
  }
}
