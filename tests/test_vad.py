from __future__ import annotations

import unittest
from typing import Any

from asmr.vad import _ProgressTrackingVadModel


class VadProgressTests(unittest.TestCase):
    def test_vad_adapter_reports_inference_chunk_progress(self) -> None:
        progress: list[float] = []

        class FakeNumpy:
            @staticmethod
            def pad(values: list[int], width: tuple[int, int], mode: str) -> list[int]:
                self.assertEqual(mode, "constant")
                return [0] * width[0] + values + [0] * width[1]

            @staticmethod
            def concatenate(chunks: list[list[int]]) -> list[int]:
                return [value for chunk in chunks for value in chunk]

            @staticmethod
            def array(values: list[int]) -> list[int]:
                return values

        class FakeModel:
            chunk_samples = 4
            sample_rate = 16000
            frame_duration_ms = 20

            def __init__(self) -> None:
                self.chunks: list[list[int]] = []

            def reset_states(self) -> None:
                return None

            def __call__(self, chunk: list[int], _sampling_rate: int) -> list[int]:
                self.chunks.append(chunk)
                return [len(chunk)]

        model = FakeModel()
        adapter = _ProgressTrackingVadModel(
            model,
            FakeNumpy(),
            progress.append,
        )
        probabilities = adapter.audio_forward(list(range(10)), 16000)

        self.assertEqual(probabilities, [4, 4, 4])
        self.assertEqual([len(chunk) for chunk in model.chunks], [4, 4, 4])
        self.assertEqual(progress, [1 / 3, 2 / 3, 1.0])


if __name__ == "__main__":
    unittest.main()
