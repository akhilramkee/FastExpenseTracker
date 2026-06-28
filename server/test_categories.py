import unittest

from categories import CANONICAL_CATEGORIES, normalize_category


class TestNormalizeCategory(unittest.TestCase):
    def test_canonical_passthrough(self):
        for category in CANONICAL_CATEGORIES:
            self.assertEqual(normalize_category(category), category)

    def test_travel_aliases(self):
        self.assertEqual(normalize_category("Travel"), "travel")
        self.assertEqual(normalize_category("accommodation"), "travel")
        self.assertEqual(normalize_category("IRCTC"), "travel")

    def test_transport_aliases(self):
        self.assertEqual(normalize_category("Transportation"), "transport")
        self.assertEqual(normalize_category("fuel"), "transport")
        self.assertEqual(normalize_category("petrol"), "transport")

    def test_healthcare_aliases(self):
        self.assertEqual(normalize_category("Healthcare"), "healthcare")
        self.assertEqual(normalize_category("health"), "healthcare")

    def test_food_and_grocery_split(self):
        self.assertEqual(normalize_category("Dining"), "food")
        self.assertEqual(normalize_category("groceries"), "groceries")

    def test_gifts_and_charity(self):
        self.assertEqual(normalize_category("Gift"), "gifts")
        self.assertEqual(normalize_category("donation"), "charity")

    def test_subscriptions(self):
        self.assertEqual(normalize_category("Subscription"), "subscriptions")

    def test_unknown_falls_back(self):
        self.assertEqual(normalize_category("randomstuff"), "uncategorized")


if __name__ == "__main__":
    unittest.main()
