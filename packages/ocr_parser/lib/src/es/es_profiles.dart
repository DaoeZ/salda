import '../core/line_rule.dart';
import '../model/raw_line.dart';

/// Perfil de cadena/establecimiento: detección + estrategia específica.
///
/// Un perfil puede aportar reglas de línea propias, ruido extra a ignorar y
/// palabras clave de total adicionales SIN tocar el parser genérico.
/// Añadir soporte para una cadena nueva = añadir un perfil aquí + corpus.
class EsMerchantProfile {
  const EsMerchantProfile({
    required this.brandKey,
    required this.displayName,
    required this.namePatterns,
    this.nif,
    required this.category,
    this.extraRules = const [],
    this.extraNoise = const [],
    this.extraTotalKeywords = const [],
  });

  final String brandKey;
  final String displayName;

  /// Se prueban (en mayúsculas) sobre las primeras líneas del ticket.
  final List<RegExp> namePatterns;

  /// NIF sin separadores: identifica la cadena aunque el nombre salga
  /// ilegible en el OCR (muy habitual en tickets térmicos).
  final String? nif;

  final String category;
  final List<LineRule> extraRules;
  final List<RegExp> extraNoise;
  final List<String> extraTotalKeywords;
}

abstract final class EsMerchantProfiles {
  static final List<EsMerchantProfile> all = [
    EsMerchantProfile(
      brandKey: 'mercadona',
      displayName: 'Mercadona',
      namePatterns: [RegExp('MERCADONA')],
      nif: 'A46103834',
      category: 'supermercado',
    ),
    EsMerchantProfile(
      brandKey: 'carrefour',
      displayName: 'Carrefour',
      namePatterns: [RegExp('CARREFOUR')],
      nif: 'A28425270',
      category: 'supermercado',
    ),
    EsMerchantProfile(
      brandKey: 'lidl',
      displayName: 'Lidl',
      namePatterns: [RegExp(r'\bLIDL\b')],
      nif: 'A60195278',
      category: 'supermercado',
    ),
    EsMerchantProfile(
      brandKey: 'dia',
      displayName: 'DIA',
      namePatterns: [RegExp('DIA RETAIL'), RegExp(r'\bDIA\b.*S\.?A')],
      nif: 'A86976495',
      category: 'supermercado',
    ),
    EsMerchantProfile(
      brandKey: 'alcampo',
      displayName: 'Alcampo',
      namePatterns: [RegExp('ALCAMPO')],
      category: 'supermercado',
    ),
    EsMerchantProfile(
      brandKey: 'eroski',
      displayName: 'Eroski',
      namePatterns: [RegExp('EROSKI')],
      category: 'supermercado',
    ),
    EsMerchantProfile(
      brandKey: 'aldi',
      displayName: 'ALDI',
      namePatterns: [RegExp(r'\bALDI\b')],
      category: 'supermercado',
    ),
    EsMerchantProfile(
      brandKey: 'consum',
      displayName: 'Consum',
      namePatterns: [RegExp(r'\bCONSUM\b')],
      category: 'supermercado',
    ),
    EsMerchantProfile(
      brandKey: 'repsol',
      displayName: 'Repsol',
      namePatterns: [RegExp('REPSOL')],
      category: 'gasolinera',
    ),
    EsMerchantProfile(
      brandKey: 'cepsa',
      displayName: 'Cepsa',
      namePatterns: [RegExp('CEPSA')],
      category: 'gasolinera',
    ),
  ];

  /// Detecta la cadena por nombre (primeras líneas) o por NIF (en cualquier
  /// parte: sobrevive a cabeceras ilegibles).
  static EsMerchantProfile? detect(List<RawLine> lines) {
    final head = lines.take(6).map((l) => l.text.toUpperCase()).toList();
    final allText = lines
        .map((l) => l.text.toUpperCase().replaceAll(RegExp(r'[.\-\s]'), ''))
        .join('\n');
    for (final profile in all) {
      for (final pattern in profile.namePatterns) {
        if (head.any(pattern.hasMatch)) return profile;
      }
      if (profile.nif != null && allText.contains(profile.nif!)) {
        return profile;
      }
    }
    return null;
  }

  /// Categoría por palabras clave cuando no hay perfil (RF-26).
  static String fallbackCategory(List<RawLine> lines) {
    final head = lines.take(6).map((l) => l.text.toUpperCase()).join(' ');
    if (RegExp(r'RESTAURANT|MESÓN|MESON|\bBAR\b|CAFETER|TABERNA|PIZZER')
        .hasMatch(head)) {
      return 'restaurante';
    }
    if (RegExp('FARMACIA').hasMatch(head)) return 'farmacia';
    if (RegExp(r'GASOLINER|ESTACION DE SERVICIO|E\.S\.').hasMatch(head)) {
      return 'gasolinera';
    }
    if (RegExp('SUPERMERCADO|SUPERMERCAT|HIPERMERCADO').hasMatch(head)) {
      return 'supermercado';
    }
    return 'otros';
  }
}
