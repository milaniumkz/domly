import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domly/ui/home_cleaning_pager.dart';
import 'package:domly/utils/home_cleaning_orders.dart';

void main() {
  test('nearest date and time first; cancelled and purchases excluded', () {
    Map<String,dynamic> order(String id, String date, String time, String status) =>
      {'id':id,'date':date,'startTime':time,'status':status};
    final items = [order('late','2026-11-02','08:00','assigned'),
      order('pm','2026-11-01','16:00','pending_assignment'),
      order('am','2026-11-01','08:00','assigned'),
      order('cancelled','2026-10-30','08:00','cancelled'),
      {...order('purchase','2026-10-29','08:00','assigned'),'type':'package_purchase'}];
    expect(orderedHomeCleanings(items).map((o)=>o['id']), ['am','pm','late']);
    expect(items.first['id'], 'late');
  });
  testWidgets('manual swipes select correct order and never auto advance', (tester) async {
    var page = 0;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(builder:(context,setState) =>
      Scaffold(body: HomeCleaningPager(index:page,count:4,
        onChanged:(next)=>setState(()=>page=next),
        child: SizedBox(width:350,height:400,child: Column(children:[
          Text('order-$page'),HomeCleaningPageIndicator(index:page,count:4,
            onChanged:(next)=>setState(()=>page=next))])))))));
    await tester.pump(const Duration(seconds:30));
    expect(find.text('order-0'),findsOneWidget);
    await tester.drag(find.byType(HomeCleaningPager),const Offset(-200,0));
    await tester.pumpAndSettle();expect(find.text('order-1'),findsOneWidget);
    await tester.pump(const Duration(seconds:30));expect(page,1);
    await tester.tap(find.byIcon(Icons.chevron_right));await tester.pumpAndSettle();expect(page,2);
    await tester.drag(find.byType(HomeCleaningPager),const Offset(200,0));
    await tester.pumpAndSettle();expect(page,1);
    expect(tester.takeException(),isNull);
  });
}
