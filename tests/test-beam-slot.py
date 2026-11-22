#!/usr/bin/env python3
"""Check that Beam agent runs share a lock and wait between runs."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "agents" / "beam-slot.sh"
COMMAND = "import json,sys,time; start=time.time(); time.sleep(0.2); json.dump([start,time.time()],open(sys.argv[1],'w'))"


class BeamSlotTests(unittest.TestCase):
    def test_runs_are_serial_and_spaced(self):
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, HOME=directory, FACTORY_BEAM_COOLDOWN_SECONDS="1")
            paths = [Path(directory) / "first.json", Path(directory) / "second.json"]
            commands = [
                ["bash", str(SCRIPT), "python3", "-c", COMMAND, str(path)]
                for path in paths
            ]
            first = subprocess.Popen(commands[0], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            second = subprocess.Popen(commands[1], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            for process in (first, second):
                _, stderr = process.communicate(timeout=10)
                self.assertEqual(process.returncode, 0, stderr.decode())
            runs = sorted(json.loads(path.read_text()) for path in paths)
            self.assertGreaterEqual(runs[1][0] - runs[0][1], 0.9)


if __name__ == "__main__":
    unittest.main()
