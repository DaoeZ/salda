import 'package:design_tokens/design_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salda_mobile/app.dart';

void main() {
  testWidgets('la app arranca y muestra el branding', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SaldaApp()));
    await tester.pumpAndSettle();

    expect(find.text(Brand.appName), findsOneWidget);
    expect(find.text(Brand.tagline), findsOneWidget);
  });
}
