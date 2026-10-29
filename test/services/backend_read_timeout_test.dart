import 'dart:async';
import 'package:domly/services/backend_api_service.dart';
import 'package:domly/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main(){
 testWidgets('stalled read fails within a bounded wait instead of hanging the screen',(tester)async{
   final response=Completer<http.Response>();
   final client=MockClient((_)=>response.future);
   final api=BackendApiService.forTesting(client:client,sessionStore:SessionStore());
   final request=api.getMap('/translations',authenticated:false);
   final check=expectLater(request,throwsA(isA<BackendApiException>().having((e)=>e.code,'code','request_timeout')));
   await tester.pump();
   await tester.pump(const Duration(seconds:21));
   await check;
   response.complete(http.Response('{"ok":true,"data":{}}',200));
   await tester.pump();
   client.close();
 });
}
