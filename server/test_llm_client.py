import unittest

from llm_client import _parse_json_content, sanitize_llm_string


class TestLlmClient(unittest.TestCase):
    def test_sanitize_llm_string_strips_pad_tokens(self):
        self.assertEqual(
            sanitize_llm_string("Zoom <pad> Subscription"),
            "Zoom Subscription",
        )
        self.assertEqual(
            sanitize_llm_string("Zoom <|pad|> Subscription"),
            "Zoom Subscription",
        )
        self.assertEqual(
            sanitize_llm_string("Dinner</pad>At Cafe"),
            "DinnerAt Cafe",
        )

    def test_parse_json_with_pad_tokens_in_raw_response(self):
        raw = (
            '{"amount": 2097.9<pad>, "category": "Travel", "confidence": 0.95, '
            '"merchant": "redBus", "is_recurring": false, '
            '"display_label": "Redbus Bus<pad><pad>"}'
        )
        result = _parse_json_content(raw)
        self.assertEqual(result["amount"], 2097.9)
        self.assertEqual(result["category"], "Travel")
        self.assertEqual(result["merchant"], "redBus")
        self.assertEqual(result["display_label"], "Redbus Bus")


if __name__ == "__main__":
    unittest.main()
