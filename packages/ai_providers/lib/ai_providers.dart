/// Sistema modular de proveedores de IA (ESPECIFICACION.md §9).
///
/// La IA es SIEMPRE el último recurso (DC-13): nunca se ejecuta sin acción
/// explícita del usuario. Las API keys nunca pasan por este paquete en
/// reposo: se inyectan por llamada desde el almacenamiento seguro.
library;

export 'src/contract.dart';
export 'src/prompt.dart' show extractionPrompt, parseAiResponse;
export 'src/providers.dart';
export 'src/registry.dart';
