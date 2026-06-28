import unittest

import llm_client
from llm_client import is_free_openrouter_model, openrouter_client_config


class TestOpenRouterClientConfig(unittest.TestCase):
    def test_free_model_detection(self):
        self.assertTrue(is_free_openrouter_model("openrouter/free"))
        self.assertTrue(is_free_openrouter_model("meta-llama/llama-3.2-3b-instruct:free"))
        self.assertFalse(is_free_openrouter_model("anthropic/claude-3.5-sonnet"))

    def test_openrouter_client_config_when_unconfigured(self):
        original = (llm_client.OPENROUTER_API_KEY, llm_client.OPENROUTER_MODEL)
        try:
            llm_client.OPENROUTER_API_KEY = ""
            llm_client.OPENROUTER_MODEL = "openrouter/free"
            config = openrouter_client_config()
            self.assertFalse(config["configured"])
            self.assertIsNone(config["openrouter_api_key"])
        finally:
            llm_client.OPENROUTER_API_KEY, llm_client.OPENROUTER_MODEL = original

    def test_openrouter_client_config_when_configured(self):
        original = (llm_client.OPENROUTER_API_KEY, llm_client.OPENROUTER_MODEL)
        try:
            llm_client.OPENROUTER_API_KEY = "test-key"
            llm_client.OPENROUTER_MODEL = "openrouter/free"
            config = openrouter_client_config()
            self.assertTrue(config["configured"])
            self.assertEqual(config["openrouter_api_key"], "test-key")
        finally:
            llm_client.OPENROUTER_API_KEY, llm_client.OPENROUTER_MODEL = original

    def test_rejects_paid_model_for_client_config(self):
        original = (llm_client.OPENROUTER_API_KEY, llm_client.OPENROUTER_MODEL)
        try:
            llm_client.OPENROUTER_API_KEY = "test-key"
            llm_client.OPENROUTER_MODEL = "anthropic/claude-3.5-sonnet"
            config = openrouter_client_config()
            self.assertFalse(config["configured"])
            self.assertIsNone(config["openrouter_api_key"])
        finally:
            llm_client.OPENROUTER_API_KEY, llm_client.OPENROUTER_MODEL = original


if __name__ == "__main__":
    unittest.main()
