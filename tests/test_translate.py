from __future__ import annotations

import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

from GalTransl.Backend.BaseTranslate import BaseTranslate, RequestHealthMetrics
from GalTransl.COpenAI import COpenAIToken
from asmr.translate import build_galtransl_config, preflight_api


class TranslationConfigTests(unittest.TestCase):
    def test_deepseek_disables_thinking_for_bulk_translation(self) -> None:
        config = build_galtransl_config(
            "https://api.deepseek.com",
            "deepseek-v4-flash",
            "secret",
            "profile.md",
        )

        backend = config["backendSpecific"]["OpenAI-Compatible"]
        self.assertEqual(
            backend["extraBody"],
            {"thinking": {"type": "disabled"}},
        )

    def test_generic_openai_endpoint_does_not_receive_deepseek_fields(self) -> None:
        config = build_galtransl_config(
            "https://example.test/v1",
            "local-model",
            "secret",
            "profile.md",
        )

        backend = config["backendSpecific"]["OpenAI-Compatible"]
        self.assertNotIn("extraBody", backend)

    @patch("requests.post")
    @patch("requests.get")
    def test_preflight_requires_a_nonempty_generation(
        self,
        get: Mock,
        post: Mock,
    ) -> None:
        get.return_value = Mock(
            status_code=200,
            json=Mock(return_value={"data": [{"id": "deepseek-v4-flash"}]}),
        )
        post.return_value = Mock(
            status_code=200,
            json=Mock(
                return_value={
                    "choices": [{"message": {"content": "OK"}}],
                }
            ),
        )

        ok, message = preflight_api(
            "https://api.deepseek.com",
            "deepseek-v4-flash",
            "secret",
        )

        self.assertTrue(ok)
        self.assertEqual(message, "API preflight passed.")
        request = post.call_args.kwargs
        self.assertEqual(
            request["json"]["thinking"],
            {"type": "disabled"},
        )

    @patch("requests.post")
    @patch("requests.get")
    def test_preflight_rejects_empty_generation(
        self,
        get: Mock,
        post: Mock,
    ) -> None:
        get.return_value = Mock(
            status_code=200,
            json=Mock(return_value={"data": [{"id": "model"}]}),
        )
        post.return_value = Mock(
            status_code=200,
            json=Mock(
                return_value={
                    "choices": [
                        {
                            "message": {
                                "content": "",
                                "reasoning_content": "still thinking",
                            }
                        }
                    ],
                }
            ),
        )

        ok, message = preflight_api(
            "https://example.test",
            "model",
            "secret",
        )

        self.assertFalse(ok)
        self.assertIn("empty text", message)


class GalTranslRequestTests(unittest.IsolatedAsyncioTestCase):
    async def test_request_forwards_provider_extra_body(self) -> None:
        class FakeCompletions:
            def __init__(self) -> None:
                self.kwargs: dict | None = None

            async def create(self, **kwargs):
                self.kwargs = kwargs
                message = SimpleNamespace(content="OK")
                return SimpleNamespace(choices=[SimpleNamespace(message=message)])

        completions = FakeCompletions()
        client = SimpleNamespace(
            chat=SimpleNamespace(completions=completions),
        )
        token = COpenAIToken(
            "secret",
            "https://api.deepseek.com/v1",
            "deepseek-v4-flash",
            stream=False,
        )
        translator = object.__new__(BaseTranslate)
        translator.client_list = [(client, token)]
        translator.tokenStrategy = "fallback"
        translator.api_timeout = 10
        translator.apiErrorWait = 0
        translator.extra_body = {"thinking": {"type": "disabled"}}
        translator.global_request_rpm = 0
        translator.pj_config = SimpleNamespace(stop_event=None)
        translator.request_health_metrics = RequestHealthMetrics()

        result, _ = await translator.ask_chatbot(
            prompt="Reply with OK.",
            stream=False,
        )

        self.assertEqual(result, "OK")
        self.assertIsNotNone(completions.kwargs)
        self.assertEqual(
            completions.kwargs["extra_body"],
            {"thinking": {"type": "disabled"}},
        )


if __name__ == "__main__":
    unittest.main()
