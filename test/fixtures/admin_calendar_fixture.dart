Map<String, dynamic> adminCalendarFixture() => {
      'from': '2026-11-01',
      'to': '2026-11-30',
      'today': '2026-11-28',
      'areaNorm': 220,
      'areaMaximum': 250,
      'updatedAt': '2026-11-28T08:45:00Z',
      'cleaners': [
        {
          'id': 'a',
          'full_name': 'Айнура',
          'phone': '+77000000011',
          'status': 'approved',
          'verification_status': 'approved'
        },
        {
          'id': 'b',
          'full_name': 'Назгуль',
          'phone': '+77000000022',
          'status': 'approved',
          'verification_status': 'approved'
        },
        {
          'id': 'c',
          'full_name': 'Без графика',
          'status': 'approved',
          'verification_status': 'approved'
        },
      ],
      'orders': [
        {
          'id': 'team',
          'numeric_id': 101,
          'service_date': '2026-11-28',
          'scheduled_date': '2026-11-28',
          'start_time': '08:00:00',
          'end_time': '13:20:00',
          'estimated_duration_minutes': 320,
          'status': 'assigned',
          'area': '400.00',
          'required_cleaners': 2,
          'customer_name': 'Мария',
          'customer_phone': '+77000000033',
          'street': 'Тестовая',
          'house': '1',
          'apartment': '2'
        },
        {
          'id': 'done',
          'numeric_id': 102,
          'service_date': '2026-11-28',
          'start_time': '14:00',
          'end_time': '15:00',
          'estimated_duration_minutes': 60,
          'status': 'completed',
          'area': 30,
          'customer_name': 'Ирина'
        },
        {
          'id': 'waiting',
          'numeric_id': 103,
          'service_date': '2026-11-28',
          'start_time': '16:00',
          'end_time': '17:00',
          'estimated_duration_minutes': 60,
          'status': 'waiting_cleaner',
          'area': 80,
          'customer_name': 'Олег'
        },
        {
          'id': 'cancelled',
          'numeric_id': 104,
          'service_date': '2026-11-28',
          'start_time': '15:00',
          'end_time': '16:00',
          'estimated_duration_minutes': 60,
          'status': 'cancelled',
          'area': 999,
          'customer_name': 'Отменённый клиент'
        },
      ],
      'assignments': [
        {
          'order_id': 'team',
          'cleaner_id': 'a',
          'allocated_area': '200.00',
          'member_status': 'accepted'
        },
        {
          'order_id': 'team',
          'cleaner_id': 'b',
          'allocated_area': '200.00',
          'member_status': 'accepted'
        },
        {
          'order_id': 'done',
          'cleaner_id': 'a',
          'allocated_area': 30,
          'member_status': 'completed'
        },
        {
          'order_id': 'cancelled',
          'cleaner_id': 'a',
          'allocated_area': 999,
          'member_status': 'accepted'
        },
      ],
      'workingDays': [
        {
          'cleaner_id': 'a',
          'service_date': '2026-11-28',
          'start_time': '08:00',
          'end_time': '18:00'
        },
        {
          'cleaner_id': 'b',
          'service_date': '2026-11-28',
          'start_time': '12:00',
          'end_time': '20:00'
        },
      ],
      'approvedWeeks': [
        {'cleaner_id': 'a', 'week_start': '2026-11-23'},
        {'cleaner_id': 'b', 'week_start': '2026-11-23'}
      ],
    };
