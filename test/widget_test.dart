import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/main.dart';

void main() {
  testWidgets('App startet mit Werkzeugleiste', (tester) async {
    await tester.pumpWidget(const MindFlowApp());
    await tester.pump();
    expect(find.byTooltip('Stift'), findsOneWidget);
    expect(find.byTooltip('Radierer'), findsOneWidget);
  });
}
