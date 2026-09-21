#!/usr/bin/env python3
"""Exercise offline formula generation; fixture bytes are not signed releases."""

import hashlib
import itertools
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


RENDERER = Path(__file__).resolve().with_name("render-homebrew-formula.sh")
VERSION = "0.1.11"


class HomebrewFormulaTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="axorc-formula-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name) / "verified artifacts"
        self.root.mkdir()

    def artifact(self, architecture):
        archive = self.root / f"axorc-{VERSION}-macos-{architecture}.zip"
        archive.write_bytes(f"fixture {architecture}".encode())
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        checksum = archive.with_suffix(".zip.sha256")
        checksum.write_text(f"{digest}  {archive.name}\n")
        return archive, checksum, digest

    def render(self, *args, error=None):
        result = subprocess.run(
            ["/bin/bash", str(RENDERER), *map(str, args)],
            capture_output=True, text=True, check=False,
        )
        if error:
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertIn(error, result.stderr)
        else:
            self.assertEqual(result.returncode, 0, result.stderr)
            syntax = subprocess.run(
                ["ruby", "-c"], input=result.stdout,
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(syntax.returncode, 0, syntax.stderr)
            self.assertIn('skip_clean "bin/axorc"', result.stdout)
            self.assertIn('"--verify", "--strict"', result.stdout)
            self.assertIn('"anchor apple generic"', result.stdout)
            self.assertNotIn("@", result.stdout)
        return result.stdout

    def test_legacy_checksum_and_universal_directory_match(self):
        _, _, digest = self.artifact("universal")
        legacy = self.render(VERSION, digest)
        self.assertEqual(legacy, self.render(VERSION, "--artifacts", self.root))
        self.assertIn(f'macos-universal.zip"\n  sha256 "{digest}"', legacy)
        self.assertIn('assert_equal %w[arm64 x86_64]', legacy)
        self.assertNotIn("on_arch_conditional", legacy)

    def test_complete_thin_set(self):
        hashes = {arch: self.artifact(arch)[2] for arch in ("universal", "arm64", "x86_64")}
        formula = self.render(VERSION, "--artifacts", self.root)
        for arch, condition in (("arm64", "arm"), ("x86_64", "intel")):
            self.assertIn(f'    {condition}: "https://github.com/openclaw/AXorcist/releases/download/v{VERSION}/axorc-{VERSION}-macos-{arch}.zip",', formula)
            self.assertIn(f'    {condition}: "{hashes[arch]}",', formula)
        self.assertNotIn("macos-universal.zip", formula)
        self.assertIn('[Hardware::CPU.arm? ? "arm64" : "x86_64"]', formula)

    @unittest.skipUnless(shutil.which("brew"), "Homebrew is required for its formula audit")
    def test_homebrew_components_order(self):
        digest = self.artifact("universal")[2]
        self.artifact("arm64")
        self.artifact("x86_64")
        formulas = []
        for mode, args in (("universal", (digest,)), ("thin", ("--artifacts", self.root))):
            path = self.root / mode / "Formula" / "axorc.rb"
            path.parent.mkdir(parents=True)
            path.write_text(self.render(VERSION, *args))
            formulas.append(str(path))
        result = subprocess.run(
            ["brew", "style", "--only-cops=FormulaAudit/ComponentsOrder", *formulas],
            env={**os.environ, "HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ANALYTICS": "1"},
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_every_partial_thin_set_fails(self):
        self.artifact("universal")
        files = [path for arch in ("arm64", "x86_64") for path in self.artifact(arch)[:2]]
        contents = {path: path.read_bytes() for path in files}
        for count in range(1, len(files)):
            for present in itertools.combinations(files, count):
                with self.subTest(present=[path.name for path in present]):
                    for path in files:
                        path.unlink(missing_ok=True)
                    for path in present:
                        path.write_bytes(contents[path])
                    self.render(VERSION, "--artifacts", self.root, error="Missing archive/checksum pair")

    def test_universal_pair_is_required(self):
        for missing in (0, 1):
            files = self.artifact("universal")
            files[missing].unlink()
            self.render(VERSION, "--artifacts", self.root, error="Missing archive/checksum pair")

    def test_corrupt_archive_and_wrong_checksum_filename_fail(self):
        for arch in ("universal", "arm64", "x86_64"):
            self.artifact(arch)
        for arch in ("universal", "arm64", "x86_64"):
            with self.subTest(architecture=arch):
                archive, checksum, digest = self.artifact(arch)
                archive.write_bytes(b"corrupted")
                self.render(VERSION, "--artifacts", self.root, error="Checksum mismatch")
                archive, checksum, digest = self.artifact(arch)
                checksum.write_text(f"{digest}  another.zip\n")
                self.render(VERSION, "--artifacts", self.root, error="Invalid checksum record")
                self.artifact(arch)

    def test_invalid_arguments_fail(self):
        self.render("bad-version", "a" * 64, error="Version must")
        self.render(VERSION, "bad-hash", error="SHA-256 must")
        self.render(VERSION, "--unknown", self.root, error="Usage:")
        self.render(error="Usage:")


if __name__ == "__main__":
    unittest.main()
