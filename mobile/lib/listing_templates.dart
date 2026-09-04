const listingCategoryOrder = [
  'goods',
  'wanted',
  'services',
  'jobs',
  'rent',
  'free',
  'lost_found',
];

const listingCategoryLabels = {
  'goods': 'Товары',
  'wanted': 'Куплю',
  'services': 'Услуги',
  'jobs': 'Работа',
  'rent': 'Аренда',
  'free': 'Отдам',
  'lost_found': 'Потеряшки',
};

String listingPriceLabel(Map<dynamic, dynamic> item) {
  final cat = item['category']?.toString();
  if (cat == 'free') return 'Отдам';
  final raw = item['price'];
  if (raw == null) return '';
  final n = raw is num ? raw : num.tryParse('$raw');
  if (n == null) return '';
  final s = n == n.roundToDouble() ? '${n.toInt()}' : '$n';
  if (cat == 'wanted') return 'до $s ₽';
  return '$s ₽';
}

class ListingTemplate {
  const ListingTemplate({
    required this.id,
    required this.category,
    required this.chipLabel,
    required this.titleHint,
    required this.descriptionHint,
    required this.exampleTitle,
    required this.exampleDescription,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  final String id;
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
    id: 'sell',
    category: 'goods',
    chipLabel: 'Продам',
    titleHint: 'Что продаёте и в каком состоянии',
    descriptionHint: 'Состояние, размер, где посмотреть, торг',
    exampleTitle: 'Продам велосипед, Сакмара',
    exampleDescription:
        'Велосипед взрослый, на ходу, торг уместен. Можно посмотреть в Сакмаре на выходных. Напишите в чат.',
    emptyTitle: 'Пока нет товаров',
    emptySubtitle: 'Пример: «Продам велосипед, Сакмара». Коротко: что, состояние, цена.',
  ),
  ListingTemplate(
    id: 'wanted',
    category: 'wanted',
    chipLabel: 'Куплю',
    titleHint: 'Что ищете и в каком селе',
    descriptionHint: 'Какое состояние подойдёт, до какой цены, куда привезти',
    exampleTitle: 'Куплю холодильник, Сакмара или область',
    exampleDescription:
        'Ищу рабочий холодильник, не огромный. Могу забрать сам по области. Напишите в чат, договоримся о цене.',
    emptyTitle: 'Пока никто ничего не ищет',
    emptySubtitle: 'Пример: «Куплю холодильник, заберу сам». Что нужно и до какой цены.',
  ),
  ListingTemplate(
    id: 'services',
    category: 'services',
    chipLabel: 'Услуги',
    titleHint: 'Какую услугу предлагаете',
    descriptionHint: 'Что входит, по каким посёлкам, сёлам и городам выезжаете, как считается цена',
    exampleTitle: 'Соберу теплицу, выезд по области',
    exampleDescription:
        'Соберу теплицу или парник, инструмент свой. Выезд по Оренбургской области. Напишите в чат — скажу, сколько выйдет.',
    emptyTitle: 'Пока нет услуг',
    emptySubtitle: 'Пример: «Соберу теплицу, выезд по области». Что делаете и где.',
  ),
  ListingTemplate(
    id: 'job_seek',
    category: 'jobs',
    chipLabel: 'Ищу работу',
    titleHint: 'Кем хотите работать и где',
    descriptionHint: 'Опыт, график, когда можете выйти',
    exampleTitle: 'Ищу работу продавцом в Сакмаре',
    exampleDescription:
        'Ищу работу продавцом или кассиром, опыт есть. График 5/2 или 2/2. Могу выйти на этой неделе. Напишите в чат.',
    emptyTitle: 'Пока нет объявлений о работе',
    emptySubtitle: 'Пример: «Ищу работу продавцом в Сакмаре, график 5/2». Укажите опыт и когда можете выйти.',
  ),
  ListingTemplate(
    id: 'job_hire',
    category: 'jobs',
    chipLabel: 'Требуется',
    titleHint: 'Кого ищете и куда',
    descriptionHint: 'Обязанности, график, оплата, как связаться',
    exampleTitle: 'Нужен продавец в магазин, Сакмара',
    exampleDescription:
        'Ищем продавца в продуктовый, график 2/2. Опыт желателен, научим. Напишите в чат или позвоните.',
    emptyTitle: 'Пока нет объявлений о работе',
    emptySubtitle: 'Пример: «Нужен продавец в Сакмаре». График и чем предстоит заниматься.',
  ),
  ListingTemplate(
    id: 'rent_out',
    category: 'rent',
    chipLabel: 'Сдам',
    titleHint: 'Что сдаёте и где',
    descriptionHint: 'Комнаты, мебель, кому можно, цена в месяц',
    exampleTitle: 'Сдам комнату в Сакмаре',
    exampleDescription:
        'Комната в доме, можно с мебелью. Для одного человека. Залог и оплата по месяцу. Напишите в чат.',
    emptyTitle: 'Пока нет аренды',
    emptySubtitle: 'Пример: «Сдам комнату в Сакмаре». Где, кому и за сколько в месяц.',
  ),
  ListingTemplate(
    id: 'rent_in',
    category: 'rent',
    chipLabel: 'Сниму',
    titleHint: 'Что ищете и на какой срок',
    descriptionHint: 'Семья или один, с какого числа, до какой цены',
    exampleTitle: 'Сниму квартиру или дом в Сакмаре',
    exampleDescription:
        'Семья из трёх человек, с 1 сентября. Можно в селе или рядом. Напишите в чат, договоримся.',
    emptyTitle: 'Пока нет аренды',
    emptySubtitle: 'Пример: «Сниму дом в Сакмаре с осени». На сколько человек и с какого числа.',
  ),
  ListingTemplate(
    id: 'free',
    category: 'free',
    chipLabel: 'Отдам',
    titleHint: 'Что отдаёте и в каком состоянии',
    descriptionHint: 'Размер, состояние, где забрать, до какого числа',
    exampleTitle: 'Отдам диван, самовывоз из Сакмары',
    exampleDescription:
        'Отдам старый диван, сидеть можно. Самовывоз из Сакмары, лучше в выходные. Напишите в чат, договоримся о времени.',
    emptyTitle: 'Пока никто ничего не отдаёт',
    emptySubtitle: 'Пример: «Отдам диван, самовывоз из Сакмары». Коротко: что, состояние, где забрать.',
  ),
  ListingTemplate(
    id: 'lost',
    category: 'lost_found',
    chipLabel: 'Потерял…',
    titleHint: 'Что потеряли и где',
    descriptionHint: 'Приметы, когда, где видели в последний раз',
    exampleTitle: 'Потерял рыжего кота у школы в Сакмаре',
    exampleDescription:
        'Вчера вечером у школы пропал рыжий кот, ошейник синий. Если видели — напишите в чат. Фото приложу.',
    emptyTitle: 'Потеряшек пока нет',
    emptySubtitle: 'Пример: «Потерял рыжего кота у школы в Сакмаре». Приметы, когда и где видели.',
  ),
  ListingTemplate(
    id: 'found',
    category: 'lost_found',
    chipLabel: 'Нашёл',
    titleHint: 'Что нашли и где',
    descriptionHint: 'Приметы, когда и где нашли, как забрать',
    exampleTitle: 'Нашёл ключи у магазина в Сакмаре',
    exampleDescription:
        'Сегодня у магазина нашёл связку ключей, брелок синий. Могу отдать в Сакмаре. Напишите в чат.',
    emptyTitle: 'Потеряшек пока нет',
    emptySubtitle: 'Пример: «Нашёл ключи у магазина в Сакмаре». Что, когда и где.',
  ),
];

ListingTemplate? templateById(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final t in listingTemplates) {
    if (t.id == id) return t;
  }
  return null;
}

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
