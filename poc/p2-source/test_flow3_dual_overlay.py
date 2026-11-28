"""Offline regression for the source integration; no provider or TV."""
import json
import tempfile
import textwrap
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import Mock
from flow3_dual_overlay import OWNER_RECIPE,TV_RECIPE,plan,transform


class DualOverlayTests(unittest.TestCase):
    def test_owner_loop_three_subtitle_slots_plus_independent_movie_slot(self):
        r=json.loads(OWNER_RECIPE.read_text())
        old,new=r["rules"][0]
        self.assertEqual(transform(old,r["rules"]),new)
        with self.assertRaisesRegex(ValueError,"ANCHOR_DRIFT"):
            transform(new,r["rules"])
        self.assertNotIn("if not active and",new)
        self.assertIn("available = 3 - len(active)",new)
        self.assertIn("active=movie_active",new)
        # Run the exact loop body for two ticks with fake executor/Futures.
        # Three unfinished G1 jobs must not prevent a newly arriving G2.
        # A failed G2 poll must not terminate or block the G1 path.
        for failure in ("none","g1","g2"):
            with self.subTest(failure=failure):
                class End(Exception):pass
                class Future:
                    def done(self):return False
                class Pool:
                    def __init__(self,**kw):self.assert_workers(kw)
                    def assert_workers(self,kw):
                        if kw["max_workers"]!=4:raise AssertionError("pool capacity")
                    def __enter__(self):return self
                    def __exit__(self,*args):pass
                    def submit(self,work):return Future()
                g1_calls=[];g2_calls=[];errors=[];ticks=[]
                def g1(**kw):
                    g1_calls.append(kw["max_events"])
                    if failure=="g1":raise RuntimeError("G1")
                    for _ in range(kw["max_events"]):kw["submit"](lambda:None)
                def g2(**kw):
                    g2_calls.append(len(kw["active"]))
                    if failure=="g2":raise RuntimeError("G2")
                    kw["submit"](lambda:None)
                def tick(_):
                    ticks.append(1)
                    if len(ticks)==2:raise End
                # Source contains an actual import inside the movie branch.
                env=dict(ThreadPoolExecutor=Pool,Future=Future,
                         consume_inert_runner_wakes=lambda:None,
                         poll_private_events=g1,poll_owner_g2_idle=g2,
                         owner_full_trace=lambda code,**kw:errors.append(code),
                         trusted_v3_factory=SimpleNamespace(g2_discover=lambda:None),
                         private_root=None,processor=None,emit=Mock(),cache_root=None,
                         time=SimpleNamespace(sleep=tick),interval_seconds=0)
                code=textwrap.dedent(new+"                    time.sleep(interval_seconds)\n")
                with self.assertRaises(End):exec(compile(code,"owner_loop","exec"),env)
                self.assertEqual(len(ticks),2)
                self.assertEqual(g1_calls[0],3)
                self.assertEqual(g2_calls[0],0)
                if failure=="g1":self.assertIn("OWNER_G1_POLL_FAILED",errors)
                if failure=="g2":self.assertIn("OWNER_G2_POLL_FAILED",errors)
                if failure=="none":self.assertEqual((g1_calls,g2_calls),([3],[0]))

    def test_paired_origin_exact_media_and_one_shot(self):
        r=json.loads(TV_RECIPE.read_text())
        p=r["rules"]
        launch="\n".join(x[1] for x in p["src/launchActions.ts"])
        self.assertIn("pairedRemote = false",launch)
        self.assertIn("pairedRemote === true && raw",launch)
        self.assertIn("currentRoute.value !== originRoute",launch)
        self.assertIn("queue[index].hash?.toLowerCase() !== hash",launch)
        self.assertIn("runLaunchParams(d.params, true)",str(p["src/platform/androidRemote.ts"]))
        act="\n".join(x[1] for x in p[next(k for k in p if k.endswith("PlayerActivity.kt"))])
        self.assertIn("requestVietsubForCurrent(current)",act)
        self.assertIn("consumed.contains(id)",act)
        self.assertLess(act.index("putBoolean(id, true).commit()"),act.rindex("requestVietsubForCurrent(current)"))
        self.assertEqual(act.count("requestFlow3Vietsub()"),2)
        self.assertNotIn("goTo(i",act)
        self.assertEqual(act.count("P3SelectedMediaPublisher.requestViewer("),1)
        screen="\n".join(x[1] for x in p["src/screens/NativePlayer.tsx"])
        self.assertIn("flow3Vietsub ? 'vlc' : engineFor",screen)
        self.assertIn("!flow3Vietsub && s.videoPlayer",screen)

    def test_anchor_drift_refused_before_any_write(self):
        with tempfile.TemporaryDirectory() as d:
            r=Path(d)
            a=r/"first.ts";b=r/"second.ts"
            a.write_text("old");b.write_text("unexpected")
            recipe={"schema":"TTV-FLOW3-DUAL-TV-V1","rules":{
                "first.ts":[["old","new"]],"second.ts":[["old","new"]]}}
            with self.assertRaisesRegex(ValueError,"ANCHOR_DRIFT"):
                plan(r,"tv",recipe)
            self.assertEqual(a.read_text(),"old")


if __name__=="__main__":
    unittest.main()
