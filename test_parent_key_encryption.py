#!/usr/bin/env python3
"""
Test script to encrypt a message using parent's RSA public key
This replicates the child app logic of encrypting messages before sending to parent
"""

from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.backends import default_backend
import base64


def encrypt_with_parent_public_key(plaintext_message: str, public_key_pem: str) -> str:
    """
    Encrypt a plaintext message using the parent's RSA public key
    
    Args:
        plaintext_message: The message to encrypt (e.g., time extension reason)
        public_key_pem: The parent's public key in PEM format
        
    Returns:
        Base64-encoded encrypted message
    """
    try:
        # Parse the PEM-formatted public key
        public_key = serialization.load_pem_public_key(
            public_key_pem.encode('utf-8'),
            backend=default_backend()
        )
        
        # Encrypt the message using PKCS1 v1.5 padding
        # This matches the default encryption in Flutter's encrypt package
        encrypted = public_key.encrypt(
            plaintext_message.encode('utf-8'),
            padding.PKCS1v15()
        )
        
        # Return base64-encoded encrypted data
        encrypted_base64 = base64.b64encode(encrypted).decode('utf-8')
        return encrypted_base64
        
    except Exception as e:
        print(f"❌ Encryption failed: {e}")
        raise


def decrypt_with_private_key(encrypted_base64: str, private_key_pem: str) -> str:
    """
    Decrypt a message using the RSA private key (for testing)
    
    Args:
        encrypted_base64: Base64-encoded encrypted message
        private_key_pem: The private key in PEM format
        
    Returns:
        Decrypted plaintext message
    """
    try:
        # Parse the PEM-formatted private key
        private_key = serialization.load_pem_private_key(
            private_key_pem.encode('utf-8'),
            password=None,
            backend=default_backend()
        )
        
        # Decode base64
        encrypted = base64.b64decode(encrypted_base64)
        
        # Decrypt using PKCS1 v1.5 padding (matches Flutter)
        decrypted = private_key.decrypt(
            encrypted,
            padding.PKCS1v15()
        )
        
        return decrypted.decode('utf-8')
        
    except Exception as e:
        print(f"❌ Decryption failed: {e}")
        raise


def generate_test_keypair():
    """Generate a test RSA keypair for demonstration"""
    # Generate private key
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
        backend=default_backend()
    )
    
    # Get public key
    public_key = private_key.public_key()
    
    # Serialize to PEM format
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    ).decode('utf-8')
    
    public_pem = public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    ).decode('utf-8')
    
    return private_pem, public_pem


def main():
    """Main test function - encrypt message with parent's public key"""
    print("=" * 60)
    print("🔐 PARENT PUBLIC KEY ENCRYPTION")
    print("   Padding: PKCS1 v1.5 (matches Flutter encrypt package)")
    print("=" * 60)
    print("\n📋 EXPECTED PUBLIC KEY FORMAT:")
    print("-" * 60)
    print("""
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyRQ3jJmN5V3K8hP2xLzM
wK4vN9Bh3xGt7fQ2sL6mP8jK3nV5rT9wX4yH2qL7vC8uN1pR6sT3kW9xL4mP2jK5
nV8rT6wX1yH9qL4vC5uN8pR3sT6kW2xL1mP9jK2nV5rT3wX8yH6qL1vC2uN5pR9s
T3kW6xL8mP5jK9nV2rT6wX4yH3qL8vC9uN1pR2sT7kW3xL1mP8jK6nV9rT5wX2yH
7qL4vC6uN3pR8sT1kW9xL5mP2jK8nV6rT9wX7yH1qL3vC8uN6pR5sT4kW2xL3mP7
jK1nV4rT8wX9yH5qL2vC1uN7pR6sT9kW8xL4mP1jK7nV3rT2wX6yH8qL9vC3uN2p
RwIDAQAB
-----END PUBLIC KEY-----

Notes:
- Must start with: -----BEGIN PUBLIC KEY-----
- Must end with: -----END PUBLIC KEY-----
- Base64 content can be single line or split into 64-char lines
- No extra spaces or characters
    """)
    
    print("=" * 60)
    print("\nEnter the parent's PUBLIC KEY (paste entire PEM including headers):")
    print("Type/paste the key, then press Enter twice when done:")
    print("-" * 60)
    
    # Read multi-line public key input
    public_key_lines = []
    while True:
        line = input()
        if line == "" and len(public_key_lines) > 0:
            break
        if line:
            public_key_lines.append(line)
    
    public_key_pem = '\n'.join(public_key_lines)
    
    # Handle JSON-escaped format (replace literal \n with actual newlines)
    if '\\n' in public_key_pem:
        print("\n⚠️  Detected JSON-escaped format (\\n), converting to proper PEM format...")
        public_key_pem = public_key_pem.replace('\\n', '\n')
    
    # Validate key format
    if not public_key_pem.strip().startswith('-----BEGIN PUBLIC KEY-----'):
        print("\n❌ ERROR: Public key must start with '-----BEGIN PUBLIC KEY-----'")
        return
    
    if not public_key_pem.strip().endswith('-----END PUBLIC KEY-----'):
        print("\n❌ ERROR: Public key must end with '-----END PUBLIC KEY-----'")
        return
    
    print("\n" + "=" * 60)
    print("Enter the MESSAGE to encrypt:")
    print("-" * 60)
    message = input()
    
    if not message:
        print("\n❌ ERROR: Message cannot be empty")
        return
    
    print("\n" + "=" * 60)
    print("🔒 ENCRYPTING...")
    print("=" * 60)
    
    try:
        # Encrypt using parent's public key
        encrypted = encrypt_with_parent_public_key(message, public_key_pem)
        
        print("\n✅ ENCRYPTION SUCCESSFUL!")
        print("=" * 60)
        print("📤 ENCRYPTED MESSAGE (Base64):")
        print("=" * 60)
        print(encrypted)
        print("=" * 60)
        
    except Exception as e:
        print(f"\n❌ ENCRYPTION FAILED: {e}")
        print("\nPlease check:")
        print("1. Public key format is correct (PEM format)")
        print("2. Key includes BEGIN/END headers")
        print("3. No extra spaces or characters")
    

if __name__ == "__main__":
    main()
