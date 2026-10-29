import '../services/backend_api_service.dart';
import 'user_error_message.dart';

String bookingErrorMessage(Object error){
 if(error is BackendApiException||UserErrorMessage.isAuthError(error))return UserErrorMessage.message(error);
 final text=error.toString();
 if(text.contains('Slot ')&&text.contains(' is unavailable'))return 'Это время уже недоступно. Обновите список и выберите другое время.';
 if(text.contains('Cleaning can only be booked at least'))return 'Выберите время, которое еще не прошло.';
 if(text.contains('Cleaning cannot be booked in the past'))return 'Дата уже прошла. Выберите сегодня или любой следующий день.';
 return UserErrorMessage.message(error,fallback:'Проверьте выбранное время и попробуйте снова.');
}
