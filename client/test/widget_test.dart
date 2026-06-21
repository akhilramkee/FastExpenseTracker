import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:client/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('App renders dashboard screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ExpenseTrackerApp());

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, 'TapEx');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
