import 'package:domly/utils/booking_error_message.dart';
import 'package:domly/services/backend_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
void main(){
 test('booking failure keeps the actual server reason instead of blaming time for every error',(){
   expect(bookingErrorMessage(const BackendApiException(code:'no_cleanings_left',message:'В пакете не осталось доступных уборок.',statusCode:400)),'В пакете не осталось доступных уборок.');
   expect(bookingErrorMessage(const BackendApiException(code:'invalid_order_time',message:'Уборка должна закончиться до 21:00.',statusCode:400)),'Уборка должна закончиться до 21:00.');
 });
}
