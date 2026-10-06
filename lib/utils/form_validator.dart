/// Client-side validation utilities
/// Prevents bad data from reaching Firestore

class ValidationResult {
  final bool isValid;
  final String? error;

  const ValidationResult.valid()
      : isValid = true,
        error = null;
  const ValidationResult.invalid(String this.error) : isValid = false;
}

class FormValidator {
  /// Validate apartment area
  /// Rules: must be between 20 and 500 m²
  static ValidationResult validateArea(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const ValidationResult.invalid('Введите площадь квартиры');
    }

    final area = double.tryParse(value.trim());
    if (area == null) {
      return const ValidationResult.invalid('Площадь должна быть числом');
    }

    if (area < 20) {
      return const ValidationResult.invalid('Минимальная площадь: 20 м²');
    }

    if (area > 500) {
      return const ValidationResult.invalid('Максимальная площадь: 500 м²');
    }

    return const ValidationResult.valid();
  }

  /// Validate phone number
  /// Rules: must start with +, contain only digits, spaces, dashes, parens
  static ValidationResult validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const ValidationResult.invalid('Введите номер телефона');
    }

    final phone = value.trim();
    if (!phone.startsWith('+')) {
      return const ValidationResult.invalid('Номер должен начинаться с +');
    }

    final digitsOnly = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (!RegExp(r'^\+\d{7,15}$').hasMatch(digitsOnly)) {
      return const ValidationResult.invalid('Неверный формат номера');
    }

    return const ValidationResult.valid();
  }

  /// Validate full name
  /// Rules: at least 2 characters, letters and spaces only
  static ValidationResult validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const ValidationResult.invalid('Введите ФИО');
    }

    final name = value.trim();
    if (name.length < 2) {
      return const ValidationResult.invalid(
          'Имя слишком короткое (мин. 2 символа)');
    }

    if (name.length > 100) {
      return const ValidationResult.invalid(
          'Имя слишком длинное (макс. 100 символов)');
    }

    return const ValidationResult.valid();
  }

  /// Validate email (optional field)
  static ValidationResult validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const ValidationResult.valid(); // Email is optional
    }

    final email = value.trim();
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      return const ValidationResult.invalid('Неверный формат email');
    }

    return const ValidationResult.valid();
  }

  /// Validate price amount
  /// Rules: must be positive number
  static ValidationResult validatePrice(num? value) {
    if (value == null) {
      return const ValidationResult.invalid('Цена не указана');
    }

    if (value <= 0) {
      return const ValidationResult.invalid('Цена должна быть больше 0');
    }

    if (value > 10000000) {
      return const ValidationResult.invalid('Цена слишком высокая');
    }

    return const ValidationResult.valid();
  }

  /// Validate date is in the future
  static ValidationResult validateFutureDate(DateTime? date,
      {String? fieldName}) {
    if (date == null) {
      return ValidationResult.invalid('${fieldName ?? 'Дата'} не указана');
    }

    final now = DateTime.now();
    if (date.isBefore(now)) {
      return ValidationResult.invalid(
          '${fieldName ?? 'Дата'} должна быть в будущем');
    }

    return const ValidationResult.valid();
  }

  /// Validate area confirmation (for bonus)
  static ValidationResult validateAreaConfirmation({
    String? area,
    bool hasPhoto = false,
  }) {
    final areaResult = validateArea(area);
    if (!areaResult.isValid) {
      return areaResult;
    }

    if (!hasPhoto) {
      return const ValidationResult.invalid('Загрузите фото техплана');
    }

    return const ValidationResult.valid();
  }

  /// Validate order form before submission
  static ValidationResult validateOrderForm({
    String? area,
    String? package,
    int? price,
    String? accessMethod,
  }) {
    final areaResult = validateArea(area);
    if (!areaResult.isValid) return areaResult;

    final priceResult = validatePrice(price);
    if (!priceResult.isValid) return priceResult;

    if (package == null || package.isEmpty) {
      return const ValidationResult.invalid('Выберите пакет');
    }

    if (accessMethod == null || accessMethod.isEmpty) {
      return const ValidationResult.invalid('Укажите способ доступа');
    }

    return const ValidationResult.valid();
  }
}

/// Input formatters
class InputFormatters {
  /// Allow only digits and one decimal point
  static String filterDecimalInput(String text) {
    return text.replaceAll(RegExp(r'[^\d.]'), '');
  }

  /// Allow only digits, spaces, dashes, parens, and leading +
  static String filterPhoneInput(String text) {
    if (text.isEmpty) return '';
    final cleaned = text.replaceAll(RegExp(r'[^\d\s\-\(\)\+]'), '');
    if (cleaned.isNotEmpty && !cleaned.startsWith('+')) {
      return '+$cleaned';
    }
    return cleaned;
  }

  /// Allow only letters, spaces, hyphens
  static String filterNameInput(String text) {
    return text.replaceAll(RegExp(r'[^\w\s\-а-яА-ЯёЁa-zA-Z]'), '');
  }
}
