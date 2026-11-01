import importlib.util
import tempfile
import unittest
from pathlib import Path


SPEC = importlib.util.spec_from_file_location(
    "proposal_status", Path(__file__).resolve().parents[1] / "proposal-status.py"
)
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


class ProposalStatusTests(unittest.TestCase):
    def test_legacy_horizontal_status(self):
        text = "# Record\n\n| Status | Date |\n|---|---|\n| Accepted | 2026-01-01 |\n"
        self.assertEqual(audit.metadata(text)["status"], "Accepted")

    def test_current_metadata_stops_before_body_examples(self):
        text = "| **Status** | Accepted |\n| **Adoption** | **Complete** — verified |\n\n## Example\n| **Adoption** | Not started |"
        self.assertEqual(audit.state(audit.metadata(text)["adoption"]), "complete")

    def test_adoption_and_legacy_vocabulary(self):
        self.assertEqual(audit.state("**Not started**"), "not started")
        self.assertEqual(audit.state("implementable — slice 1 delivered"), "accepted")
        self.assertEqual(audit.state("Partial, then reverted"), "partial")

    def test_escaped_pipe_does_not_shift_columns(self):
        self.assertEqual(audit.cells(r"| a \| b | Partial |"), [r"a \| b", "Partial"])

    def test_inventory_flags_drift_and_preserves_legacy_adoption(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            adr = root / "docs/proposals/adr"
            rfc = root / "docs/proposals/rfc"
            adr.mkdir(parents=True)
            rfc.mkdir()
            (adr / "README.md").write_text(
                "| [ADR-001](ADR-001-old/) | Old | Accepted | Complete | — |\n"
                "| [ADR-002](ADR-002-new/) | New | Accepted | Not started | — |\n"
            )
            for name, body in [
                ("ADR-001-old", "# Old\n| Status | Date |\n|---|---|\n| Accepted | 2026 |"),
                ("ADR-002-new", "# New\n| **Status** | Accepted |\n| **Adoption** | Complete |"),
            ]:
                (adr / name).mkdir()
                (adr / name / "README.md").write_text(body)
            (rfc / "README.md").write_text(
                "| [RFC-0001](RFC-0001/) | Research | platform | P2 | researching |\n"
            )
            (rfc / "RFC-0001").mkdir()
            (rfc / "RFC-0001/research.md").write_text("# Research\n")
            records, problems = audit.inventory(root)
            self.assertEqual(len(records), 3)
            self.assertEqual(records[0]["adoption_source"], "legacy index")
            self.assertEqual(records[2]["status"], "researching")
            self.assertEqual(problems, ["ADR-002: adoption complete; index not started"])


if __name__ == "__main__":
    unittest.main()
