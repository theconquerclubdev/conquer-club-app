/// Small text-normalization helpers used across signup / profile forms.
///
/// Rule of thumb:
/// - Names            -> Title Case            ("AMAY KOLEKAR" -> "Amay Kolekar")
/// - Email             -> lowercase, trimmed    ("Amay@GMAIL.com " -> "amay@gmail.com")
/// - Password          -> left exactly as typed (case-sensitive, never touched)

/// Converts a name typed in any case into standard Title Case.
/// Handles extra spaces and multi-word names (first/middle/last).
/// Also title-cases hyphenated names like "mary-jane" -> "Mary-Jane".
String toTitleCase(String input) {
  final trimmed = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.isEmpty) return trimmed;

  return trimmed.split(' ').map((word) {
    if (word.isEmpty) return word;
    // Handle hyphenated parts, e.g. "kolekar-patil" -> "Kolekar-Patil"
    return word.split('-').map((part) {
      if (part.isEmpty) return part;
      return part[0].toUpperCase() + part.substring(1).toLowerCase();
    }).join('-');
  }).join(' ');
}

/// Normalizes an email address: trims whitespace and lowercases it.
/// Emails are case-insensitive by convention, and storing them lowercase
/// avoids duplicate-account bugs where "Amay@Gmail.com" and
/// "amay@gmail.com" are treated as different users.
String normalizeEmail(String input) {
  return input.trim().toLowerCase();
}

/// Password is intentionally NOT normalized — case matters for passwords,
/// so we only trim accidental leading/trailing whitespace (e.g. from
/// autofill), never change letter casing.
String normalizePassword(String input) {
  return input.trim();
}
