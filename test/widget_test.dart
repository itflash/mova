import 'package:flutter_test/flutter_test.dart';
import 'package:mova/app/app.dart';

void main() {
  testWidgets('renders native shell tabs', (tester) async {
    await tester.pumpWidget(const SeedanceNativeApp());

    expect(find.text('创作'), findsWidgets);
    expect(find.text('素材'), findsOneWidget);
    expect(find.text('任务'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('描述'), findsOneWidget);
  });
}
