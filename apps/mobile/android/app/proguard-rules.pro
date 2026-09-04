# Reglas de R8 para la build de release.
#
# ML Kit Text Recognition v2 reparte el reconocedor en cinco artefactos: el
# LATINO (`com.google.mlkit:text-recognition`) y uno por escritura para
# chino, devanagari, japonés y coreano. El plugin
# `google_mlkit_text_recognition` declara el latino como `implementation` —o
# sea, empaquetado— y los otros cuatro como `compileOnly`:
#
#   implementation("com.google.mlkit:text-recognition:16.0.1")
#   compileOnly("com.google.mlkit:text-recognition-chinese:16.0.1")
#   compileOnly("com.google.mlkit:text-recognition-devanagari:16.0.1")
#   compileOnly("com.google.mlkit:text-recognition-japanese:16.0.1")
#   compileOnly("com.google.mlkit:text-recognition-korean:16.0.1")
#
# `compileOnly` significa que el plugin COMPILA contra ellos pero NO los
# distribuye: cada app añade solo las escrituras que use. Salda escanea
# tickets españoles y usa `TextRecognitionScript.latin` y nada más
# (features/scan/data/mlkit_receipt_ocr.dart), así que esas cuatro clases no
# están —ni deben estar— en el APK: son ~15 MB de modelos por escritura.
#
# R8 ve la referencia desde el código Java del plugin, no encuentra la clase
# y aborta. La corrección correcta NO es empaquetar los modelos ni silenciar
# el paquete entero, sino declarar que faltan A PROPÓSITO exactamente esas
# cuatro opciones. Si algún día se añade una escritura, basta con añadir su
# dependencia y BORRAR su línea de aquí.
#
# Se listan clase a clase (y sus `$Builder`) en vez de un comodín sobre
# `com.google.mlkit.**`: silenciar el paquete entero ocultaría la ausencia
# real de una clase del reconocedor latino, que sí sería un fallo.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder

# El reconocedor LATINO sí se usa y llega por reflexión desde ML Kit: se
# conserva explícitamente para que el shrinker no lo retire al no ver una
# referencia directa desde Dart.
-keep class com.google.mlkit.vision.text.latin.** { *; }
-keep class com.google.mlkit.vision.text.TextRecognition { *; }
-keep class com.google.mlkit.vision.text.TextRecognizerOptionsInterface { *; }
