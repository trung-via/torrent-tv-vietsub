"""Offline tests for opt-in timed EN->VI translation handoff, no AI calls."""
import hashlib
import unittest

from opensubtitles import Asset, SubtitleApiError
from timed_translation import iter_batches, parse_srt, translate_en_to_vi


def source_srt(count=3):
    return "\n\n".join(
        f"{i}\n00:{i // 60:02d}:{i % 60:02d},000 --> 00:{i // 60:02d}:{i % 60:02d},900\nHello {i}"
        for i in range(1, count + 1)
    ).encode("utf-8")


def source_asset(count=3, language="en"):
    content = source_srt(count)
    return Asset(17, language, "srt", content, hashlib.sha256(content).hexdigest(), count)


def authorized(source, adapter):
    return translate_en_to_vi(source, adapter,
                              source_rights_confirmed=True,
                              outbound_content_approved=True,
                              api_cost_approved=True)


class TimedTests(unittest.TestCase):
    def test_unauthorized_cannot_call_api_adapter(self):
        calls = []
        def forbidden(batch):
            calls.append(batch)
            raise AssertionError("API must not run")
        source = source_asset()
        for flags in ({}, {"source_rights_confirmed": True},
                      {"source_rights_confirmed": True,
                       "outbound_content_approved": True},
                      {"source_rights_confirmed": True,
                       "outbound_content_approved": True,
                       "api_cost_approved": False}):
            with self.subTest(flags=flags):
                with self.assertRaisesRegex(SubtitleApiError,
                                            "TRANSLATION_CONSENT_REQUIRED"):
                    translate_en_to_vi(source, forbidden, **flags)
        self.assertEqual(calls, [])

    def test_exact_ids_times_are_retained_and_output_vi(self):
        original = source_asset(4)
        def adapter(batch):
            return {cue.ordinal: f"Xin chào {cue.ordinal}" for cue in batch.source}
        output = authorized(original, adapter)
        self.assertEqual(output.cue_count, 4)
        self.assertEqual(output.source_sha256, original.sha256)
        self.assertEqual(output.qa_status, "STRUCTURAL_PASS_SEMANTIC_UNVERIFIED")
        self.assertEqual([(x.ordinal, x.timeline) for x in parse_srt(original.contents)],
                         [(x.ordinal, x.timeline) for x in parse_srt(output.contents)])
        self.assertIn("Xin chào 4".encode("utf-8"), output.contents)
        self.assertEqual(output.output_sha256,
                         hashlib.sha256(output.contents).hexdigest())

    def test_batches_lean120_and_4_neighbour_context(self):
        source = source_asset(125)
        batches = iter_batches(parse_srt(source.contents))
        self.assertEqual([len(b.source) for b in batches], [120, 5])
        self.assertEqual([c.ordinal for c in batches[1].before],
                         [117, 118, 119, 120])
        self.assertEqual([c.ordinal for c in batches[0].after],
                         [121, 122, 123, 124])
        self.assertEqual([c.ordinal for c in batches[1].source],
                         [121, 122, 123, 124, 125])

    def test_121_cue_translated_without_id_shift(self):
        source = source_asset(121)
        calls = []
        def adapter(batch):
            calls.append(tuple(c.ordinal for c in batch.source))
            return {c.ordinal: f"Việt {c.ordinal}" for c in batch.source}
        output = authorized(source, adapter)
        self.assertEqual(len(calls), 2)
        self.assertEqual(output.cue_count, 121)
        self.assertEqual(parse_srt(output.contents)[-1].ordinal, 121)

    def test_missing_or_unexpected_ids_fail(self):
        for adapter in (
            lambda batch: {},
            lambda batch: {1: "Một", 2: "Hai", 3: "Ba", 4: "Thừa"},
            lambda batch: {"1": "Một", "2": "Hai", "3": "Ba"},
        ):
            with self.subTest(adapter=str(adapter)):
                with self.assertRaisesRegex(SubtitleApiError,
                                            "TRANSLATION_ID_COVERAGE_MISMATCH"):
                    authorized(source_asset(), adapter)

    def test_no_english_or_unsupported_format(self):
        calls = []
        def adapter(batch):
            calls.append(batch)
            return {}
        with self.assertRaisesRegex(SubtitleApiError,
                                    "TRANSLATION_SOURCE_MUST_BE_EN_SRT"):
            authorized(source_asset(language="vi"), adapter)
        self.assertEqual(calls, [])

    def test_bad_digest_and_source_count_block_before_model(self):
        asset = source_asset()
        asset_wrong = Asset(asset.file_id, "en", "srt", asset.contents,
                            "0" * 64, asset.cues)
        with self.assertRaisesRegex(SubtitleApiError, "SOURCE_DIGEST_MISMATCH"):
            authorized(asset_wrong, lambda b: {})
        count_wrong = Asset(asset.file_id, "en", "srt", asset.contents,
                            asset.sha256, 55)
        with self.assertRaisesRegex(SubtitleApiError, "SOURCE_CUE_COUNT_MISMATCH"):
            authorized(count_wrong, lambda b: {})

    def test_invalid_translation_text_fails_closed(self):
        for text in ("", "   ", "<script>evil</script>", "line\nbreak", "\x00unsafe",
                     "a" * 1801):
            with self.subTest(text=text[:20]):
                def adapter(batch):
                    return {c.ordinal: text for c in batch.source}
                with self.assertRaisesRegex(SubtitleApiError,
                                            "INVALID_TRANSLATION_TEXT"):
                    authorized(source_asset(), adapter)

    def test_explicit_literal_newline_survives_srt(self):
        def adapter(batch):
            return {c.ordinal: "Xin chào\\nBạn" for c in batch.source}
        result = authorized(source_asset(), adapter)
        self.assertIn("Xin chào\nBạn".encode("utf-8"), result.contents)
        self.assertEqual(result.cue_count, 3)

    def test_invalid_cue_structure_cannot_be_sent_to_model(self):
        content = b"1\n00:00:01,000 --> 00:00:02,000\nHi\n\n2\n00:00:03,000 --> 00:00:04,000\n"
        asset = Asset(1, "en", "srt", content,
                      hashlib.sha256(content).hexdigest(), 2)
        with self.assertRaises(SubtitleApiError):
            authorized(asset, lambda b: {1: "Việt", 2: "Hai"})

    def test_id_cannot_overflow_to_next_cue(self):
        source = source_asset(4)
        def adapter(batch):
            return {c.ordinal + 1: "Sai lệch" for c in batch.source}
        with self.assertRaisesRegex(SubtitleApiError,
                                    "TRANSLATION_ID_COVERAGE_MISMATCH"):
            authorized(source, adapter)


if __name__ == "__main__":
    unittest.main()
