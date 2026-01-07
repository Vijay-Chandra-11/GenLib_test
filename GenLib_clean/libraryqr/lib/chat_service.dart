// //Rule Based AI

import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math'; // Needed for the fuzzy search algorithm

// Represents a single book's data, fetched from Firebase
class Book {
  final String title;
  final String author;
  final String genre;
  final String description;
  final int count;

  Book({
    required this.title,
    required this.author,
    required this.genre,
    required this.description,
    required this.count,
  });
}

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Caching mechanism to hold the book data
  List<Book>? _bookCache;

  // Fetches all book data from Firestore and populates the cache
  Future<void> _loadBookData() async {
    if (_bookCache != null) return; // Load only once

    final booksSnapshot = await _firestore.collection('books').get();
    _bookCache = [];
    for (var doc in booksSnapshot.docs) {
      final data = doc.data();
      _bookCache!.add(
        Book(
          title: data['title'] ?? 'Unknown Title',
          author: data['author'] ?? 'Unknown Author',
          genre: data['genre'] ?? 'Unknown Genre',
          description: data['description'] ?? 'No description available.',
          count: data['count'] ?? 0,
        ),
      );
    }
  }

  // --- Levenshtein Distance algorithm for fuzzy string matching ---
  int _calculateLevenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final matrix = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0));

    for (var i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }

    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost
        ].reduce(min);
      }
    }
    return matrix[a.length][b.length];
  }

  // --- Function to remove common "stop words" from the user's query ---
  String _cleanUserInput(String input) {
    const stopWords = [
      'who', 'is', 'the', 'author', 'of', 'what', 'about', 'description',
      'tell', 'me', 'book', 'books', 'a', 'an', 'by', 'for', 'list', 'available',
      'in', 'genre', 'written', 'give', 'written'
    ];
    // Remove punctuation and split into words
    final words = input.replaceAll(RegExp(r'[^\w\s]'), '').toLowerCase().split(' ');
    // Filter out the stop words
    final filteredWords = words.where((word) => !stopWords.contains(word));
    return filteredWords.join(' ');
  }


  // The main function that processes user input and returns a response
  Future<String> getChatbotResponse(String userInput) async {
    // Ensure book data is loaded before proceeding
    await _loadBookData();

    if (_bookCache == null || _bookCache!.isEmpty) {
      return "I'm sorry, I don't have any book information right now. Please check your connection and try again.";
    }

    final input = userInput.toLowerCase().trim();

    // --- Rule 1: Handle Greetings ---
    if (input == 'hi' || input == 'hello' || input == 'hey') {
      return "Hello! I'm Liora, your library assistant. You can ask me about a book's author, genre, or description.";
    }

    // --- Rule to list all available books ---
    if (input.contains('available books') || input.contains('what books are available')) {
      final availableBooks = _bookCache!.where((book) => book.count > 0).toList();
      if (availableBooks.isNotEmpty) {
        return "Of course! Here are the books currently available:\n\n" +
            availableBooks.map((b) => "- **${b.title}** by ${b.author} (${b.count} copies)").join('\n');
      } else {
        return "I'm sorry, it looks like there are no books available for borrowing right now.";
      }
    }

    // --- Rule to list available books in a specific genre using fuzzy search ---
    final cleanedGenreInput = _cleanUserInput(input);
    String? foundGenre;
    int bestGenreMatchDistance = 10;
    final uniqueGenres = _bookCache!.map((b) => b.genre).toSet().toList();

    for (var genre in uniqueGenres) {
      final distance = _calculateLevenshteinDistance(cleanedGenreInput, genre.toLowerCase());
      if (distance < bestGenreMatchDistance && distance < (genre.length / 2).floor()) {
        bestGenreMatchDistance = distance;
        foundGenre = genre;
      }
    }

    if (foundGenre != null && (input.contains('books') || input.contains('list') || input.contains('genre'))) {
      final availableBooksInGenre = _bookCache!
          .where((book) => book.genre == foundGenre && book.count > 0)
          .toList();

      if (availableBooksInGenre.isNotEmpty) {
        return "Certainly! Here are the available books in the **$foundGenre** genre:\n\n" +
            availableBooksInGenre
                .map((b) => "- **${b.title}** by ${b.author} (${b.count} copies)")
                .join('\n');
      } else {
        return "I'm sorry, it looks like there are no books currently available in the **$foundGenre** genre.";
      }
    }


    // --- Find a specific book using the cleaned input and fuzzy search ---
    final cleanedTitleInput = _cleanUserInput(input);
    Book? foundBook;
    int bestTitleMatchDistance = 10;

    for (var book in _bookCache!) {
      final cleanedTitle = _cleanUserInput(book.title);
      final distance = _calculateLevenshteinDistance(cleanedTitleInput, cleanedTitle);

      if (distance < bestTitleMatchDistance && distance < (cleanedTitle.length / 2).floor()) {
        bestTitleMatchDistance = distance;
        foundBook = book;
      }
    }

    // If a specific book was mentioned in the input, answer based on keywords
    if (foundBook != null) {
      if (input.contains('available') || input.contains('availability') || input.contains('avilable')) {
        if (foundBook.count > 0) {
          return "Yes, **${foundBook.title}** is available. We have ${foundBook.count} copies.";
        } else {
          return "I'm sorry, **${foundBook.title}** is currently not available.";
        }
      }

      if (input.contains('about') || input.contains('description') || input.contains('tell me about')) {
        final availability = foundBook.count > 0 ? "Available (${foundBook.count} copies)" : "Currently unavailable";
        return "**${foundBook.title}**\n\n*Status: $availability*\n\n${foundBook.description}";
      }
      if (input.contains('who wrote') || input.contains('author')) {
        return "The author of **${foundBook.title}** is ${foundBook.author}.";
      }
      if (input.contains('what genre') || input.contains('genre of')) {
        return "**${foundBook.title}** is in the **${foundBook.genre}** genre.";
      }
      return "I have information about **${foundBook.title}**. What would you like to know? You can ask about its author, genre, description, or availability.";
    }

    // --- UPDATED: More robust rule for finding books by author ---
    if (input.contains('by')) {
      final parts = input.split('by');
      if (parts.length > 1) {
        final authorName = parts[1].trim();
        final booksByAuthor = _bookCache!.where((book) => book.author.toLowerCase().contains(authorName)).toList();
        if (booksByAuthor.isNotEmpty) {
          return "Here are the books we have by **${booksByAuthor.first.author}**:\n\n" + booksByAuthor.map((b) => "- ${b.title}").join('\n');
        }
      }
    }

    // --- Final fallback rule ---
    return "I'm sorry, that book is not present in the library.";
  }
}
