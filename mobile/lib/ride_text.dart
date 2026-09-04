String rideKindLabel(String? kind) => kind == 'need' ? 'Ищу' : 'Еду';

String rideSeatsLabel(String? kind, int seats) {
  if (kind == 'need') {
    if (seats == 1) return '1 человек';
    if (seats >= 2 && seats <= 4) return '$seats человека';
    return '$seats человек';
  }
  if (seats == 1) return '1 место';
  if (seats >= 2 && seats <= 4) return '$seats места';
  return '$seats мест';
}

String rideCloseLabel(String? reason) {
  switch (reason) {
    case 'full':
      return 'Мест больше нет';
    case 'cancelled':
      return 'Поездка не состоится';
    case 'gone':
      return 'Уже уехали';
    default:
      return 'Снято';
  }
}
