// Driver estándar de integration_test. Hace falta porque `flutter test` no
// puede resolver los tests de integración en un pub workspace sin arrastrar
// también los unitarios ("cannot be run in a single invocation").
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
