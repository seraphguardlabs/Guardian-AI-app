import 'package:flutter/services.dart';
import 'dart:convert';

/// Production-ready BERT Tokenizer for Flutter
/// Implements WordPiece tokenization with vocab.txt
class BertTokenizer {
  Map<String, int> _vocab = {};
  Map<int, String> _reverseVocab = {};
  bool _isLoaded = false;
  
  static const int _maxLength = 128;
  static const String _unkToken = '[UNK]';
  static const String _padToken = '[PAD]';
  static const String _clsToken = '[CLS]';
  static const String _sepToken = '[SEP]';

  Future<void> loadVocab() async {
    if (_isLoaded) return;
    
    try {
      // Load vocab.txt from assets
      final vocabString = await rootBundle.loadString('assets/models/vocab.txt');
      final lines = vocabString.split('\n');
      
      for (int i = 0; i < lines.length; i++) {
        final token = lines[i].trim();
        if (token.isNotEmpty) {
          _vocab[token] = i;
          _reverseVocab[i] = token;
        }
      }
      
      _isLoaded = true;
      print('✅ BERT vocabulary loaded: ${_vocab.length} tokens');
    } catch (e) {
      print('❌ Failed to load vocab: $e');
      rethrow;
    }
  }

  /// Tokenize text and return input_ids and attention_mask
  Map<String, List<int>> encode(String text, {int maxLength = _maxLength}) {
    if (!_isLoaded) {
      throw Exception('Tokenizer not loaded. Call loadVocab() first.');
    }
    
    // Lowercase and basic cleaning
    text = text.toLowerCase().trim();
    
    // Tokenize
    final tokens = _tokenize(text);
    
    // Add special tokens
    final fullTokens = [_clsToken, ...tokens, _sepToken];
    
    // Convert to IDs
    final inputIds = fullTokens.map((token) {
      return _vocab[token] ?? _vocab[_unkToken]!;
    }).toList();
    
    // Create attention mask
    final attentionMask = List<int>.filled(inputIds.length, 1);
    
    // Pad or truncate to maxLength
    if (inputIds.length < maxLength) {
      final padId = _vocab[_padToken]!;
      while (inputIds.length < maxLength) {
        inputIds.add(padId);
        attentionMask.add(0);
      }
    } else if (inputIds.length > maxLength) {
      inputIds.removeRange(maxLength, inputIds.length);
      attentionMask.removeRange(maxLength, attentionMask.length);
    }
    
    return {
      'input_ids': inputIds,
      'attention_mask': attentionMask
    };
  }

  /// WordPiece tokenization
  List<String> _tokenize(String text) {
    final words = text.split(RegExp(r'\s+'));
    final tokens = <String>[];
    
    for (final word in words) {
      if (word.isEmpty) continue;
      
      // Try to find word in vocab
      if (_vocab.containsKey(word)) {
        tokens.add(word);
        continue;
      }
      
      // WordPiece algorithm
      final subTokens = _wordPieceTokenize(word);
      tokens.addAll(subTokens);
    }
    
    return tokens;
  }

  /// WordPiece sub-word tokenization
  List<String> _wordPieceTokenize(String word) {
    final tokens = <String>[];
    int start = 0;
    
    while (start < word.length) {
      int end = word.length;
      String? foundToken;
      
      // Greedy longest-match-first
      while (start < end) {
        String substr = word.substring(start, end);
        if (start > 0) {
          substr = '##$substr'; // WordPiece continuation marker
        }
        
        if (_vocab.containsKey(substr)) {
          foundToken = substr;
          break;
        }
        end--;
      }
      
      if (foundToken == null) {
        tokens.add(_unkToken);
        break;
      }
      
      tokens.add(foundToken);
      start = end;
    }
    
    return tokens;
  }
}
