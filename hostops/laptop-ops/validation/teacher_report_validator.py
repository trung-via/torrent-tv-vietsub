"""Pure Teacher report validation. No provider, filesystem or network operations."""
import json

SECTIONS = ("diagnosis", "demonstration_steps", "student_exercise",
            "grading_rubric", "latency_experiment", "limitations", "observed_evidence")


def validate_teacher_report(exit_code, response, permission_denied=False):
    """Return a disposition and parsed report; never treat exit 0 alone as PASS."""
    if permission_denied:
        return "FAILED_PERMISSION", None
    if type(exit_code) is not int or exit_code != 0:
        return "FAILED_PROVIDER_EXIT", None
    if not isinstance(response, str) or not response.strip():
        return "FAILED_EMPTY_RESPONSE", None
    try:
        report = json.loads(response)
    except ValueError:
        return "FAILED_REPORT_JSON", None
    if not isinstance(report, dict) or report.get("status") != "REPORT_READY":
        return "FAILED_REPORT_STATUS", None
    recipe = report.get("recipe_v5")
    if not isinstance(recipe, list) or not 1 <= len(recipe) <= 30 or any(
        not isinstance(step, str) or not step.strip() or len(step) > 1500 for step in recipe
    ):
        return "FAILED_RECIPE", None
    def populated(value):
        if isinstance(value, str):
            return bool(value.strip())
        if isinstance(value, (list, dict)):
            return bool(value) and any(populated(x) for x in (value.values() if isinstance(value, dict) else value))
        return False
    if any(not populated(report.get(key)) for key in SECTIONS):
        return "FAILED_REPORT_SECTIONS", None
    budget = report.get("acquisition_budget_seconds")
    if type(budget) is not int or not 1 <= budget <= 120:
        return "FAILED_BUDGET", None
    return "REPORT_READY_FOR_BRAIN_REVIEW", report


if __name__ == "__main__":
    import unittest

    class TeacherReportTests(unittest.TestCase):
        def setUp(self):
            self.good = {key: "Evidence or training instruction" for key in SECTIONS}
            self.good.update(status="REPORT_READY", recipe_v5=["Compare release metadata."], acquisition_budget_seconds=60)

        def test_observed_tr18(self):
            self.assertEqual(validate_teacher_report(0, "", True)[0], "FAILED_PERMISSION")

        def test_empty_without_denial(self):
            self.assertEqual(validate_teacher_report(0, " ")[0], "FAILED_EMPTY_RESPONSE")

        def test_exit(self):
            self.assertEqual(validate_teacher_report(1, json.dumps(self.good))[0], "FAILED_PROVIDER_EXIT")

        def test_invalid_json(self):
            self.assertEqual(validate_teacher_report(0, "not JSON")[0], "FAILED_REPORT_JSON")

        def test_invalid_status(self):
            self.good["status"] = "UNKNOWN"
            self.assertEqual(validate_teacher_report(0, json.dumps(self.good))[0], "FAILED_REPORT_STATUS")

        def test_missing_recipe(self):
            self.good["recipe_v5"] = []
            self.assertEqual(validate_teacher_report(0, json.dumps(self.good))[0], "FAILED_RECIPE")

        def test_empty_section(self):
            self.good["diagnosis"] = [" "]
            self.assertEqual(validate_teacher_report(0, json.dumps(self.good))[0], "FAILED_REPORT_SECTIONS")

        def test_invalid_budget(self):
            self.good["acquisition_budget_seconds"] = True
            self.assertEqual(validate_teacher_report(0, json.dumps(self.good))[0], "FAILED_BUDGET")

        def test_valid_is_not_brain_pass(self):
            self.assertEqual(validate_teacher_report(0, json.dumps(self.good)), ("REPORT_READY_FOR_BRAIN_REVIEW", self.good))

    unittest.main()
