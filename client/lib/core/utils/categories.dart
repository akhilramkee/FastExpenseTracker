/// Canonical expense categories — keep in sync with server/categories.py.
const canonicalCategories = <String>[
  'groceries',
  'food',
  'travel',
  'transport',
  'healthcare',
  'subscriptions',
  'gifts',
  'charity',
  'communication',
  'utilities',
  'entertainment',
  'shopping',
  'work',
  'education',
  'housing',
  'personal',
  'fitness',
  'uncategorized',
];

const _categoryAliases = <String, String>{
  'grocery': 'groceries',
  'supermarket': 'groceries',
  'market': 'groceries',
  'dining': 'food',
  'restaurant': 'food',
  'restaurants': 'food',
  'cafe': 'food',
  'coffee': 'food',
  'sweets': 'food',
  'snacks': 'food',
  'travel': 'travel',
  'trip': 'travel',
  'vacation': 'travel',
  'accommodation': 'travel',
  'lodging': 'travel',
  'hotel': 'travel',
  'hotels': 'travel',
  'flight': 'travel',
  'flights': 'travel',
  'airbnb': 'travel',
  'train': 'travel',
  'trains': 'travel',
  'irctc': 'travel',
  'redbus': 'travel',
  'transport': 'transport',
  'transportation': 'transport',
  'transit': 'transport',
  'commute': 'transport',
  'fuel': 'transport',
  'gas': 'transport',
  'petrol': 'transport',
  'diesel': 'transport',
  'taxi': 'transport',
  'cab': 'transport',
  'rideshare': 'transport',
  'uber': 'transport',
  'lyft': 'transport',
  'rapido': 'transport',
  'parking': 'transport',
  'auto': 'transport',
  'bus': 'transport',
  'healthcare': 'healthcare',
  'health': 'healthcare',
  'medical': 'healthcare',
  'medicine': 'healthcare',
  'hospital': 'healthcare',
  'pharmacy': 'healthcare',
  'doctor': 'healthcare',
  'clinic': 'healthcare',
  'subscription': 'subscriptions',
  'subscriptions': 'subscriptions',
  'software': 'subscriptions',
  'saas': 'subscriptions',
  'gift': 'gifts',
  'gifts': 'gifts',
  'present': 'gifts',
  'wedding': 'gifts',
  'charity': 'charity',
  'donation': 'charity',
  'donations': 'charity',
  'temple': 'charity',
  'communication': 'communication',
  'telecom': 'communication',
  'phone': 'communication',
  'mobile': 'communication',
  'recharge': 'communication',
  'internet': 'communication',
  'utilities': 'utilities',
  'utility': 'utilities',
  'wifi': 'utilities',
  'electricity': 'utilities',
  'water': 'utilities',
  'broadband': 'utilities',
  'entertainment': 'entertainment',
  'movies': 'entertainment',
  'streaming': 'entertainment',
  'games': 'entertainment',
  'night': 'entertainment',
  'nightlife': 'entertainment',
  'shopping': 'shopping',
  'retail': 'shopping',
  'amazon': 'shopping',
  'work': 'work',
  'office': 'work',
  'business': 'work',
  'education': 'education',
  'school': 'education',
  'books': 'education',
  'course': 'education',
  'housing': 'housing',
  'rent': 'housing',
  'mortgage': 'housing',
  'personal': 'personal',
  'misc': 'personal',
  'miscellaneous': 'personal',
  'fitness': 'fitness',
  'gym': 'fitness',
  'sports': 'fitness',
  'uncategorized': 'uncategorized',
  'other': 'uncategorized',
};

String _slugify(String value) {
  return value
      .toLowerCase()
      .trim()
      .replaceAll(' ', '_')
      .replaceAll('-', '_')
      .replaceAll('/', '_');
}

String normalizeCategory(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'uncategorized';

  final slug = _slugify(raw);
  if (canonicalCategories.contains(slug)) return slug;

  final alias = _categoryAliases[slug];
  if (alias != null) return alias;

  for (final entry in _categoryAliases.entries) {
    if (slug.contains(entry.key) || entry.key.contains(slug)) {
      return entry.value;
    }
  }

  return 'uncategorized';
}

String formatCategoryLabel(String tag) {
  final normalized = normalizeCategory(tag);
  if (normalized.isEmpty) return 'Uncategorized';
  return normalized[0].toUpperCase() + normalized.substring(1);
}

/// LLM prompt block — keep in sync with server/categories.py category_prompt_block().
const categoryPromptBlock = '''
category must be exactly one of these canonical values:
groceries, food, travel, transport, healthcare, subscriptions, gifts, charity, communication, utilities, entertainment, shopping, work, education, housing, personal, fitness, uncategorized

Classification rules:
- travel: intercity trips (trains, flights, redbus, hotels, airbnb, long-distance buses)
- transport: local commute (taxi, rapido, fuel, petrol, parking, short local rides)
- food: restaurants, dining, sweets, snacks (not groceries)
- groceries: supermarket, departmental store, produce runs
- healthcare: hospital, pharmacy, doctor, medical
- subscriptions: recurring software or media services
- gifts: presents for people (wedding gifts, toys, cakes for others)
- charity: donations and temple offerings
- communication: phone and mobile recharges
- utilities: home wifi, electricity, water''';
