"""Offline V13.1 Owner contract; never starts AGY, Chrome, network or TV."""
from dataclasses import replace
import hashlib
import io
import tempfile
from pathlib import Path
import unittest
from unittest import mock
import zipfile

from agy_opensubtitles_acquisition import AgyEnglishUnavailable
from agy_v13_browser_evidence import (
    BrowserEvidence, BrowserRequest, make_v13_acquirer, verify_evidence, timeline_observation,
)
from automatic_vietsub_flow import build_owner_auto_flow
from brain_english_inbox import acquire_brain_english
from matcher import Media
from test_agy_opensubtitles_acquisition import NAME, MATCH, srt

MEDIA = Media("personal", "a" * 40, 2, NAME)
URL = "https://www.opensubtitles.org"
LIST = URL + "/en/search/sublanguageid-eng/moviename-example"
TITLE = "Example Film subtitles English | 2 subtitles"


def out(n, data):
    return {"event": n, "tool": "evaluate_script", "output": data}


def proof(blob=None):
    blob = srt() if blob is None else blob
    def detail(n):
        return {"url": URL + f"/en/subtitles/{n}/example-en",
                "btnVisible": True, "fieldsetText": "Visible download",
                "downloadHref": f"/en/subtitleserve/sub/{n}"}
    rows = [{"href": "/en/subtitles/111/example-en", "lang": "english",
             "release": MATCH, "release_group": "grp"},
            {"href": "/en/subtitles/222/example-en", "lang": "flag en",
             "release": "Example.Film.2017.BluRay-ALT", "release_group": "alt"}]
    listing = {"url": LIST, "heading": "Example Film English",
               "page_title": TITLE, "count_scope": "filtered_results",
               "count_label": TITLE, "total_english": 2,
               "has_next": False, "rows": rows}
    click = {"clicked": True, "id": "111", "pageUrl": detail(111)["url"],
             "href": detail(111)["downloadHref"], "downloaderChecked": False}
    artifact = {"copied_to_job": True, "candidate_refs": ["/en/download/sub/111"],
                "bytes": len(blob), "sha256": hashlib.sha256(blob).hexdigest()}
    return BrowserEvidence(MEDIA, 7200, 24, (out(1, listing), out(2, detail(222)),
                          out(3, detail(111)), out(4, click)), (artifact,), blob, True)


class V13EvidenceTests(unittest.TestCase):
    def verify(self, evidence):
        return verify_evidence(BrowserRequest(MEDIA), evidence)

    def test_exact_verified_artifact_and_recipe(self):
        self.assertEqual(self.verify(proof()).cues, 125)
        prompt = BrowserRequest(MEDIA).prompt(duration_seconds=7200, fps=29.97)
        for value in ("RIFE interpolated", "next_href", "OpenSubtitles.org", "7200"):
            self.assertIn(value, prompt)
        self.assertNotIn("a" * 40, prompt)

    def test_zip_only_one_srt(self):
        b = io.BytesIO()
        with zipfile.ZipFile(b, "w") as z:
            z.writestr("english.srt", srt())
        self.assertEqual(self.verify(proof(b.getvalue())).cues, 125)
        b = io.BytesIO()
        with zipfile.ZipFile(b, "w") as z:
            z.writestr("a.srt", srt())
            z.writestr("b.srt", srt())
        with self.assertRaises(AgyEnglishUnavailable):
            self.verify(proof(b.getvalue()))

    def test_reject_wrong_media_stale_hash_and_bad_timing(self):
        p = proof()
        for wrong in (replace(p, media=replace(MEDIA, file_index=3)),
                      replace(p, fresh_download_verified=False),
                      replace(p, download_bytes=b"other"),
                      replace(p, fps=float("nan")),
                      proof(b"not an srt")):
            with self.subTest(wrong=wrong), self.assertRaises(AgyEnglishUnavailable):
                self.verify(wrong)

    def test_wrong_candidate_binding_and_incomplete_list(self):
        p = proof()
        a = dict(p.artifacts[0], candidate_refs=["/en/download/sub/222"])
        with self.assertRaises(AgyEnglishUnavailable):
            self.verify(replace(p, artifacts=(a,)))
        listing = out(1, dict(p.outcomes[0]["output"], has_next=True))
        with self.assertRaises(AgyEnglishUnavailable):
            self.verify(replace(p, outcomes=(listing, *p.outcomes[1:])))

    def test_complete_unrelated_list_cannot_satisfy_selected_group(self):
        p = proof()
        listing = out(1, dict(p.outcomes[0]["output"], has_next=True))
        other = dict(p.outcomes[0]["output"], url=LIST + "-other")
        other["rows"] = [dict(row, href=f"/en/subtitles/{300+i}/other-en")
                         for i, row in enumerate(other["rows"])]
        with self.assertRaises(AgyEnglishUnavailable):
            self.verify(replace(p, outcomes=(listing, out(2, other), *p.outcomes[1:])))

    def test_conflicting_terminal_page_is_rejected(self):
        p = proof()
        listing = p.outcomes[0]["output"]
        conflicting = out(0, dict(listing, has_next=True,
            next_href=LIST + "/offset-40"))
        with self.assertRaises(AgyEnglishUnavailable):
            self.verify(replace(p, outcomes=(conflicting, *p.outcomes)))

    def test_duration_overrun_is_rejected_without_retiming(self):
        with self.assertRaisesRegex(AgyEnglishUnavailable, "OVERRUN"):
            self.verify(replace(proof(), duration_seconds=1))

    def test_selected_release_does_not_require_second_family_detail(self):
        p = proof()
        incomplete = (p.outcomes[0], *p.outcomes[2:])
        self.assertEqual(self.verify(replace(p, outcomes=incomplete)).cues, 125)

    def test_explicit_runtime_conflict_cannot_pass_same_release_match(self):
        p = proof()
        chosen = dict(p.outcomes[2]["output"], fieldsetText="Visible download\nRuntime: 01:30:00")
        events = (*p.outcomes[:2], out(3, chosen), p.outcomes[3])
        with self.assertRaisesRegex(AgyEnglishUnavailable, "EXPLICIT_RUNTIME_CONFLICT"):
            self.verify(replace(p, outcomes=events))
        matching = dict(chosen, fieldsetText="Visible download\nRuntime: 120 minutes")
        self.assertEqual(self.verify(replace(p, outcomes=(*p.outcomes[:2], out(3, matching), p.outcomes[3]))).cues,125)

    def test_timeline_observation_never_claims_complete_dialogue(self):
        p = proof()
        observation = timeline_observation(self.verify(p).contents, p.duration_seconds)
        self.assertEqual(observation["cues"],125)
        self.assertEqual(observation["first_10m_cues"],125)
        self.assertLess(observation["timeline_span_fraction"],0.1)
        self.assertEqual(observation["dialogue_completeness"],"UNVERIFIED")
        self.assertEqual(observation["sync"],"UNVERIFIED")

    def test_native_selected_movie_accepts_encoding_difference_only(self):
        p = proof()
        listing = dict(p.outcomes[0]["output"])
        listing["rows"] = [dict(listing["rows"][0],
            release="Example.Film.2017.2160p.x264-OTHER.srt"), listing["rows"][1]]
        self.assertEqual(self.verify(replace(p, outcomes=(out(1, listing), *p.outcomes[1:]))).cues, 125)
        for bad in ("Example.Film.2018.2160p.x264-OTHER.srt",
                    "Example.Film.2160p.x264-OTHER.srt",
                    "Example.Film.2.2017.2160p.x264-OTHER.srt"):
            listing["rows"][0] = dict(listing["rows"][0], release=bad)
            with self.assertRaisesRegex(AgyEnglishUnavailable, "RELEASE_MISMATCH"):
                self.verify(replace(p, outcomes=(out(1, listing), *p.outcomes[1:])))

    def test_existing_matcher_still_rejects_different_movie(self):
        p = proof()
        listing = dict(p.outcomes[0]["output"])
        listing["rows"] = [dict(listing["rows"][0], release="Different.Film.2017.1080p.BluRay.x265-GRP.srt"),
                           listing["rows"][1]]
        with self.assertRaisesRegex(AgyEnglishUnavailable, "RELEASE_MISMATCH"):
            self.verify(replace(p, outcomes=(out(1, listing), *p.outcomes[1:])))

    def test_owner_injection_is_lazy_and_default_unchanged(self):
        calls = []
        def runner(req, folder):
            calls.append((req, folder))
            return proof()
        with tempfile.TemporaryDirectory() as temp, mock.patch.dict(
                "os.environ", {"CI": "", "GITHUB_ACTIONS": ""}, clear=True):
            root = Path(temp).resolve()
            default = build_owner_auto_flow(enabled=True, cache_root=root / "cache",
                                            state_root=root / "state")
            candidate = build_owner_auto_flow(enabled=True, cache_root=root / "cache",
                                              state_root=root / "state",
                                              native_browser_runner=runner)
            self.assertIs(default.source_acquirer, acquire_brain_english)
            self.assertEqual(candidate.worker.first_window_cues, 50)
            self.assertEqual(candidate.worker.profile, default.worker.profile)
            self.assertEqual(calls, [])
            self.assertEqual(candidate.source_acquirer(MEDIA, root / "cache").cues, 125)
            self.assertEqual(len(calls), 1)
            self.assertFalse((root / "cache").exists())

    def test_runner_failure_propagates_without_fallback(self):
        calls = []
        def runner(req, folder):
            calls.append(req)
            raise AgyEnglishUnavailable("AGY_EN_TIMEOUT_RESULT_UNKNOWN")
        with self.assertRaisesRegex(AgyEnglishUnavailable, "RESULT_UNKNOWN"):
            make_v13_acquirer(runner)(MEDIA, Path("unused"))
        self.assertEqual(len(calls), 1)


if __name__ == "__main__":
    unittest.main()
