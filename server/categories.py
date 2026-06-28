"""Canonical expense categories and alias normalization."""

from __future__ import annotations

from typing import Dict, FrozenSet, List

CANONICAL_CATEGORIES: List[str] = [
    "groceries",
    "food",
    "travel",
    "transport",
    "healthcare",
    "subscriptions",
    "gifts",
    "charity",
    "communication",
    "utilities",
    "entertainment",
    "shopping",
    "work",
    "education",
    "housing",
    "personal",
    "fitness",
    "uncategorized",
]

_CANONICAL_SET: FrozenSet[str] = frozenset(CANONICAL_CATEGORIES)

# Aliases map to a single canonical slug (all keys lowercase).
_CATEGORY_ALIASES: Dict[str, str] = {
  # groceries
    "grocery": "groceries",
    "supermarket": "groceries",
    "market": "groceries",
    # food
    "dining": "food",
    "restaurant": "food",
    "restaurants": "food",
    "cafe": "food",
    "coffee": "food",
    "sweets": "food",
    "snacks": "food",
    # travel — intercity trips, lodging, long-distance transit
    "travel": "travel",
    "trip": "travel",
    "vacation": "travel",
    "accommodation": "travel",
    "lodging": "travel",
    "hotel": "travel",
    "hotels": "travel",
    "flight": "travel",
    "flights": "travel",
    "airbnb": "travel",
    "train": "travel",
    "trains": "travel",
    "irctc": "travel",
    "redbus": "travel",
    # transport — local commute, fuel, short rides
    "transport": "transport",
    "transportation": "transport",
    "transit": "transport",
    "commute": "transport",
    "fuel": "transport",
    "gas": "transport",
    "petrol": "transport",
    "diesel": "transport",
    "taxi": "transport",
    "cab": "transport",
    "rideshare": "transport",
    "uber": "transport",
    "lyft": "transport",
    "rapido": "transport",
    "parking": "transport",
    "auto": "transport",
    "bus": "transport",
    # healthcare
    "healthcare": "healthcare",
    "health": "healthcare",
    "medical": "healthcare",
    "medicine": "healthcare",
    "hospital": "healthcare",
    "pharmacy": "healthcare",
    "doctor": "healthcare",
    "clinic": "healthcare",
    # subscriptions
    "subscription": "subscriptions",
    "subscriptions": "subscriptions",
    "software": "subscriptions",
    "saas": "subscriptions",
    # gifts
    "gift": "gifts",
    "gifts": "gifts",
    "present": "gifts",
    "wedding": "gifts",
    # charity
    "charity": "charity",
    "donation": "charity",
    "donations": "charity",
    "temple": "charity",
    # communication
    "communication": "communication",
    "telecom": "communication",
    "phone": "communication",
    "mobile": "communication",
    "recharge": "communication",
    "internet": "communication",
    # utilities
    "utilities": "utilities",
    "utility": "utilities",
    "wifi": "utilities",
    "electricity": "utilities",
    "water": "utilities",
    "broadband": "utilities",
    # entertainment
    "entertainment": "entertainment",
    "movies": "entertainment",
    "streaming": "entertainment",
    "games": "entertainment",
    "night": "entertainment",
    "nightlife": "entertainment",
    # shopping
    "shopping": "shopping",
    "retail": "shopping",
    "amazon": "shopping",
    # work
    "work": "work",
    "office": "work",
    "business": "work",
    # education
    "education": "education",
    "school": "education",
    "books": "education",
    "course": "education",
    # housing
    "housing": "housing",
    "rent": "housing",
    "mortgage": "housing",
    # personal
    "personal": "personal",
    "misc": "personal",
    "miscellaneous": "personal",
    # fitness
    "fitness": "fitness",
    "gym": "fitness",
    "sports": "fitness",
    # fallback
    "uncategorized": "uncategorized",
    "other": "uncategorized",
}


def _slugify(value: str) -> str:
    return value.lower().strip().replace(" ", "_").replace("-", "_").replace("/", "_")


def normalize_category(raw: str | None) -> str:
    if not raw or not str(raw).strip():
        return "uncategorized"

    slug = _slugify(str(raw))
    if slug in _CANONICAL_SET:
        return slug

    if slug in _CATEGORY_ALIASES:
        return _CATEGORY_ALIASES[slug]

    for alias, canonical in _CATEGORY_ALIASES.items():
        if alias in slug or slug in alias:
            return canonical

    return "uncategorized"


def category_prompt_block() -> str:
    lines = [
        "category must be exactly one of these canonical values:",
        ", ".join(CANONICAL_CATEGORIES),
        "",
        "Classification rules:",
        "- travel: intercity trips (trains, flights, redbus, hotels, airbnb, long-distance buses)",
        "- transport: local commute (taxi, rapido, fuel, petrol, parking, short local rides)",
        "- food: restaurants, dining, sweets, snacks (not groceries)",
        "- groceries: supermarket, departmental store, produce runs",
        "- healthcare: hospital, pharmacy, doctor, medical",
        "- subscriptions: recurring software or media services",
        "- gifts: presents for people (wedding gifts, toys, cakes for others)",
        "- charity: donations and temple offerings",
        "- communication: phone and mobile recharges",
        "- utilities: home wifi, electricity, water",
    ]
    return "\n".join(lines)
