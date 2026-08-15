class ListingTemplate {
  const ListingTemplate({
    required this.category,
    required this.chipLabel,
    required this.titleHint,
    required this.descriptionHint,
    required this.exampleTitle,
    required this.exampleDescription,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  final String category;
  final String chipLabel;
  final String titleHint;
  final String descriptionHint;
  final String exampleTitle;
  final String exampleDescription;
  final String emptyTitle;
  final String emptySubtitle;
}

const listingTemplates = [
  ListingTemplate(
    category: 'free',
    chipLabel: 'Отдам',
    titleHint: 'Что отдаёте и в каком состоянии',
    descriptionHint: 'Размер, состояние, где забрать, до какого числа',
    exampleTitle: 'Отдам диван, самовывоз из Сакмары',
    exampleDescription:
        'Отдам старый диван, сидеть можно. Самовывоз из Сакмары, лучше в выходные. Напишите в чат, договоримся о времени.',
    emptyTitle: 'Пока никто ничего не отдаёт',
    emptySubtitle:
        'Пример: «Отдам диван, самовывоз из Сакмары». Коротко: что, состояние, где забрать.',
  ),
  ListingTemplate(
    category: 'jobs',
    chipLabel: 'Ищу работу',
    titleHint: 'Кем хотите работать и в каком селе',
    descriptionHint: 'Опыт, график, когда можете выйти',
    exampleTitle: 'Ищу работу продавцом в Сакмаре',
    exampleDescription:
        'Ищу работу продавцом или кассиром, опыт есть. График 5/2 или 2/2. Могу выйти на этой неделе. Напишите в чат.',
    emptyTitle: 'Пока нет объявлений о работе',
    emptySubtitle:
        'Пример: «Ищу работу продавцом в Сакмаре, график 5/2». Укажите опыт и когда можете выйти.',
  ),
  ListingTemplate(
    category: 'lost_found',
    chipLabel: 'Потерял…',
    titleHint: 'Что потеряли или нашли и где',
    descriptionHint: 'Приметы, когда, где видели в последний раз',
    exampleTitle: 'Потерял рыжего кота у школы в Сакмаре',
    exampleDescription:
        'Вчера вечером у школы пропал рыжий кот, ошейник синий. Если видели — напишите в чат. Фото приложу.',
    emptyTitle: 'Потеряшек пока нет',
    emptySubtitle:
        'Пример: «Потерял рыжего кота у школы в Сакмаре». Приметы, когда и где видели.',
  ),
];

ListingTemplate? templateFor(String? category) {
  if (category == null || category.isEmpty) return null;
  for (final t in listingTemplates) {
    if (t.category == category) return t;
  }
  return null;
}

({String title, String subtitle}) emptyListingCopy(String? category) {
  final t = templateFor(category);
  if (t != null) {
    return (title: t.emptyTitle, subtitle: t.emptySubtitle);
  }
  return (
    title: 'Пока нет объявлений',
    subtitle: 'Измените фильтры или подайте своё объявление',
  );
}
