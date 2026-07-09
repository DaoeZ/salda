/// Sistema modular de proveedores de IA (ESPECIFICACION.md §9).
///
/// Contrato `AiReceiptProvider` + registro con orden de preferencia y
/// fallback. Las API keys NUNCA pasan por este paquete en reposo: se
/// inyectan por llamada desde el almacenamiento seguro del dispositivo.
///
/// Se implementa en M6 (el contrato de datos `ReceiptExtraction` queda
/// fijado antes, en M2, dentro de `domain`).
library;
