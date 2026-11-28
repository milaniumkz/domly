import 'admin_order_data.dart';

Map<String, dynamic> mapAdminComplaint(Map<String, dynamic> item) => {
      ...item,
      'id': item['id'],
      'number': item['numeric_id'] ?? item['number'],
      'orderId': item['order_id'] ?? item['orderId'],
      'orderNumber': item['order_number'] ?? item['orderNumber'],
      'customerId': item['customer_id'] ?? item['customerId'],
      'customerName': item['customer_name'] ?? item['customerName'],
      'customerPhone': item['customer_phone'] ?? item['customerPhone'],
      'cleanerId': item['cleaner_id'] ?? item['cleanerId'],
      'cleanerName': item['cleaner_name'] ?? item['cleanerName'],
      'cleanerPhone': item['cleaner_phone'] ?? item['cleanerPhone'],
      'orderDate': item['scheduled_date'] ?? item['orderDate'],
      'startTime': adminClockTime(item['start_time'] ?? item['startTime']),
      'endTime': adminClockTime(item['end_time'] ?? item['endTime']),
      'orderStatus': item['order_status'] ?? item['orderStatus'],
      'text': item['body'] ?? item['text'] ?? item['title'] ?? '',
      'photoUrls': item['photo_urls'] ?? item['photoUrls'] ?? const [],
      'createdAt': item['created_at'] ?? item['createdAt'],
      'updatedAt': item['updated_at'] ?? item['updatedAt'],
    };

String complaintOrderLabel(Map<String, dynamic> item) {
  if ('${item['orderId'] ?? item['order_id'] ?? ''}'.trim().isEmpty)
    return 'Не привязана к заказу';
  final number = '${item['orderNumber'] ?? item['order_number'] ?? ''}'.trim();
  return number.isEmpty ? 'Связанный заказ' : 'Заказ №$number';
}
