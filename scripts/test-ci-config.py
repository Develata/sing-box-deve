#!/usr/bin/env python3
"""Check the CI boundaries that must survive tool and workflow updates."""
from pathlib import Path
import re
import unittest

import yaml

ROOT = Path(__file__).resolve().parent.parent


def read_yaml(path):
    # BaseLoader preserves GitHub's `on` key instead of YAML 1.1 boolean coercion.
    return yaml.load(path.read_text(), Loader=yaml.BaseLoader)


class WorkflowTests(unittest.TestCase):
    def test_remote_actions_are_pinned_and_jobs_are_bounded(self):
        for path in (ROOT / ".github/workflows").glob("*.yml"):
            workflow = read_yaml(path)
            for job in workflow["jobs"].values():
                with self.subTest(workflow=path.name):
                    self.assertGreater(int(job["timeout-minutes"]), 0)
                    self.assertLessEqual(int(job["timeout-minutes"]), 60)
                    self.check_action_refs(job.get("steps", []))
        for path in (ROOT / ".github/actions").glob("*/action.yml"):
            self.check_action_refs(read_yaml(path)["runs"]["steps"])

    def check_action_refs(self, steps):
        for step in steps:
            if "uses" in step and not step["uses"].startswith("./"):
                self.assertRegex(step["uses"], r"^[\w.-]+/[\w./-]+@[0-9a-f]{40}$")

    def test_ci_runs_both_stages_with_fail_closed_aggregate(self):
        workflow = read_yaml(ROOT / ".github/workflows/ci.yml")
        self.assertIn("pull_request", workflow["on"])
        self.assertNotIn("pull_request_target", workflow["on"])
        jobs = workflow["jobs"]
        verify = jobs["verify"]
        self.assertEqual(verify["strategy"]["matrix"]["stage"], ["lint", "regression"])
        self.assertEqual(verify["strategy"]["fail-fast"], "false")
        suite = next(s for s in verify["steps"] if "VERIFICATION_STAGE" in s.get("env", {}))
        self.assertEqual(suite["env"]["VERIFICATION_STAGE"], "${{ matrix.stage }}")
        self.assertEqual(suite["run"], 'bash scripts/sing-box-deve-pre-push.sh "$VERIFICATION_STAGE"')
        self.assertEqual(jobs["checks"]["needs"], "verify")
        self.assertEqual(jobs["checks"]["if"], "always()")
        gate = jobs["checks"]["steps"][0]
        self.assertEqual(gate["env"]["VERIFY_RESULT"], "${{ needs.verify.result }}")
        self.assertEqual(gate["run"], 'test "$VERIFY_RESULT" = success')

    def test_release_and_full_regression_keep_the_full_suite(self):
        for name, job in [("release.yml", "publish"), ("full-regression.yml", "full-regression")]:
            steps = read_yaml(ROOT / ".github/workflows" / name)["jobs"][job]["steps"]
            self.assertIn("./.github/actions/setup-verification", [s.get("uses") for s in steps])
            commands = "\n".join(s.get("run", "") for s in steps)
            self.assertRegex(commands, r"(?m)^bash scripts/sing-box-deve-pre-push\.sh$")
            self.assertIn("git diff --exit-code checksums.txt", commands)

    def test_dependabot_tracks_pinned_tools_and_actions(self):
        config = read_yaml(ROOT / ".github/dependabot.yml")
        self.assertEqual(config["version"], "2")
        self.assertEqual(
            {(u["package-ecosystem"], u["directory"]) for u in config["updates"]},
            {("github-actions", "/"), ("pip", "/scripts")},
        )
        for update in config["updates"]:
            self.assertEqual(update["schedule"]["interval"], "weekly")
        requirements = (ROOT / "scripts/requirements-ci.txt").read_text().splitlines()
        for line in requirements:
            if line and not line.startswith("#"):
                self.assertIsNotNone(re.fullmatch(r"[\w-]+==[0-9]+(?:\.[0-9]+)+", line))


if __name__ == "__main__":
    unittest.main()
