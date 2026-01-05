#!/usr/bin/env python3
"""
RSA Message Encryption Tool
Encrypts messages using RSA public key encryption (PKCS#1 OAEP)
Compatible with Guardian AI's encryption logic
"""

import base64
from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.backends import default_backend


def encrypt_message(message, public_key_pem):
    """
    Encrypt a message using RSA public key with PKCS#1 OAEP padding.
    
    Args:
        message (str): The plaintext message to encrypt
        public_key_pem (str): The RSA public key in PEM format
    
    Returns:
        str: Base64-encoded encrypted message
    
    Raises:
        ValueError: If the public key format is invalid
        Exception: If encryption fails
    """
    try:
        # Load the public key from PEM format
        public_key = serialization.load_pem_public_key(
            public_key_pem.encode('utf-8'),
            backend=default_backend()
        )
        
        # Encrypt the message using PKCS#1 OAEP padding (same as Flutter's encrypt package)
        ciphertext = public_key.encrypt(
            message.encode('utf-8'),
            padding.OAEP(
                mgf=padding.MGF1(algorithm=hashes.SHA256()),
                algorithm=hashes.SHA256(),
                label=None
            )
        )
        
        # Return base64-encoded ciphertext (compatible with Flutter/Dart base64)
        return base64.b64encode(ciphertext).decode('utf-8')
        
    except ValueError as e:
        raise ValueError(f"Invalid public key format: {e}")
    except Exception as e:
        raise Exception(f"Encryption failed: {e}")


def main():
    """
    Main function - Interactive message encryption
    """
    print("=" * 60)
    print("RSA MESSAGE ENCRYPTION TOOL")
    print("Compatible with Guardian AI Encryption Service")
    print("=" * 60)
    print()
    
    # Get message from user
    print("Enter the message to encrypt:")
    message = input("> ")
    
    if not message.strip():
        print("❌ Error: Message cannot be empty")
        return
    
    print()
    print("Enter the RSA public key in PEM format:")
    print("(Paste the complete key including BEGIN/END lines, then press Enter twice)")
    print()
    
    # Read multi-line public key input
    public_key_lines = []
    while True:
        line = input()
        if line.strip() == "" and public_key_lines:
            break
        if line.strip():
            public_key_lines.append(line)
    
    public_key_pem = '\n'.join(public_key_lines)
    
    # Validate public key format
    if not public_key_pem.startswith('-----BEGIN PUBLIC KEY-----'):
        print("❌ Error: Invalid public key format. Must start with '-----BEGIN PUBLIC KEY-----'")
        return
    
    if not public_key_pem.endswith('-----END PUBLIC KEY-----'):
        print("❌ Error: Invalid public key format. Must end with '-----END PUBLIC KEY-----'")
        return
    
    print()
    print("=" * 60)
    print("🔐 ENCRYPTING MESSAGE...")
    print("=" * 60)
    print()
    
    try:
        # Encrypt the message
        encrypted_base64 = encrypt_message(message, public_key_pem)
        
        print("✅ ENCRYPTION SUCCESSFUL!")
        print()
        print("=" * 60)
        print("📊 ENCRYPTION DETAILS:")
        print("=" * 60)
        print(f"Original message length: {len(message)} characters")
        print(f"Encrypted data length: {len(encrypted_base64)} characters (base64)")
        print(f"Encryption algorithm: RSA-2048 with PKCS#1 OAEP")
        print(f"Padding: OAEP with SHA-256")
        print()
        print("=" * 60)
        print("🔒 ENCRYPTED MESSAGE (Base64):")
        print("=" * 60)
        print(encrypted_base64)
        print("=" * 60)
        print()
        print("✅ You can now send this encrypted message securely.")
        print("   Only the holder of the corresponding private key can decrypt it.")
        print()
        
    except ValueError as e:
        print(f"❌ Error: {e}")
    except Exception as e:
        print(f"❌ Encryption failed: {e}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  Operation cancelled by user")
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
