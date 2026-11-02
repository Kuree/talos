import json
from io import BytesIO
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from utils.packaging.dev_version import development_version
from utils.packaging.check_wheels import check_binary
from utils.packaging.check_install import check_windows_dlls
from utils.packaging.publish_dev import publish, validate_archives, validate_wheels


def wheels(version="0.1.0.dev12"):
    return [Path("talos_sv-{}-py2.py3-none-manylinux_2_39_{}.whl".format(version, arch))
            for arch in ("x86_64", "aarch64")]


class VersionTest(unittest.TestCase):
    def test_bump_and_rerun(self):
        self.assertEqual(development_version("0.1.0\n", 1793232000), "0.1.0.dev1793232000")
        self.assertEqual(development_version("0.1.0.dev1793232000\n", 1793232000),
                         "0.1.0.dev1793232000")
        self.assertEqual(development_version("0.2.0.dev0", 1793232001), "0.2.0.dev1793232001")

    def test_invalid_versions(self):
        for value in ("", "0.1", "0.1.0\nmalformed", "0.1.0.devx"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                development_version(value, 12)


class ReleaseTest(unittest.TestCase):
    def test_windows_packages_reject_icu_dlls(self):
        check_windows_dlls(["bin/libxml2.dll", "bin/iconv.dll", "bin/vcruntime140.dll"])
        for name in ("talos_sv/bin/icudt78.dll", "bin/ICUUC78.DLL"):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, "without ICU"):
                check_windows_dlls([name])

    def test_windows_staging_uses_sdk_xml_without_icu(self):
        script = Path(__file__).resolve().parents[2] / "cmake/StageWindowsDLLs.cmake"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            sdk = root / "sdk"
            (sdk / "bin").mkdir(parents=True)
            for name in ("libxml2.dll", "icudt78.dll", "icuuc78.dll",
                         "iconv.dll", "charset.dll", "vcruntime140.dll", "zstd.dll"):
                (sdk / "bin" / name).write_text("SDK " + name)
            output = root / "package/bin"
            subprocess.run(["cmake", "-DSDK=" + sdk.as_posix(),
                            "-DDIRECTORIES=" + output.as_posix(), "-P", str(script)],
                           check=True, capture_output=True, text=True)
            self.assertEqual({path.name for path in output.iterdir()},
                             {"libxml2.dll", "iconv.dll", "charset.dll",
                              "vcruntime140.dll", "zstd.dll"})
            self.assertEqual((output / "libxml2.dll").read_text(), "SDK libxml2.dll")

    def test_native_windows_architecture_must_match_tag(self):
        executable = bytearray(152)
        executable[:2] = b"MZ"
        struct.pack_into("<I", executable, 0x3C, 128)
        executable[128:132] = b"PE\0\0"
        struct.pack_into("<H", executable, 132, 0xAA64)
        check_binary(BytesIO(executable), "win_arm64")
        with self.assertRaises(ValueError):
            check_binary(BytesIO(executable), "win_amd64")

    def test_windows_wheels_reject_unstripped_executables(self):
        for machine, platform in ((0x8664, "win_amd64"), (0xAA64, "win_arm64")):
            with self.subTest(platform=platform):
                executable = bytearray(152)
                executable[:2] = b"MZ"
                struct.pack_into("<I", executable, 0x3C, 128)
                executable[128:132] = b"PE\0\0"
                struct.pack_into("<H", executable, 132, machine)
                struct.pack_into("<II", executable, 140, 152, 1)
                with self.assertRaisesRegex(ValueError, "must be stripped"):
                    check_binary(BytesIO(executable), platform)
                struct.pack_into("<II", executable, 140, 0, 0)
                check_binary(BytesIO(executable), platform)

    def test_old_rerun_cannot_roll_back_newer_release(self):
        current = {"tag_name": "dev", "prerelease": True,
                   "assets": [{"name": wheels("0.1.0.dev13")[0].name}]}
        with patch("utils.packaging.publish_dev.gh", return_value=json.dumps([[current]])) as remote:
            with self.assertRaisesRegex(ValueError, "newer development release"):
                publish("owner/repo", "abc123", wheels())
            self.assertEqual(remote.call_count, 1)

    def test_archive_platform_formats_and_versions(self):
        archives = [Path("talos-sv-0.1.0.dev12-x86_64-pc-windows-msvc.zip"),
                    Path("talos-sv-0.1.0.dev12-aarch64-unknown-linux-gnu.tar.gz")]
        validate_archives(archives, "0.1.0.dev12", ["x86_64-pc-windows-msvc"])
        for inputs in ([archives[0].with_suffix(".tar.gz")],
                       [Path("talos-sv-0.1.0.dev11-aarch64-unknown-linux-gnu.tar.gz")],
                       archives * 2, []):
            with self.subTest(inputs=inputs), self.assertRaises(ValueError):
                validate_archives(inputs, "0.1.0.dev12", ["x86_64-pc-windows-msvc"])

    def test_validate_complete_set(self):
        required = ["manylinux_2_39_" + arch for arch in ("x86_64", "aarch64")]
        self.assertEqual(validate_wheels(wheels(), required), "0.1.0.dev12")
        for inputs in ([], wheels("0.1.0"), wheels() + wheels("0.1.0.dev13"), wheels()[:1]):
            with self.subTest(inputs=inputs), self.assertRaises(ValueError):
                validate_wheels(inputs, required)

    def test_reject_python_abi_and_unaudited_platform(self):
        for suffix in ("cp312-cp312-manylinux_2_39_x86_64", "py3-none-manylinux_2_39_x86_64",
                       "py2.py3-none-linux_x86_64", "py2.py3-none-any"):
            with self.subTest(suffix=suffix), self.assertRaises(ValueError):
                validate_wheels([Path("talos_sv-0.1.0.dev12-" + suffix + ".whl")], [])

    def test_publish_replaces_and_prunes_only_talos_assets(self):
        calls = []
        old = wheels("0.1.0.dev11")[0].name
        old_archive = "talos-sv-0.1.0.dev11-x86_64-pc-windows-msvc.zip"
        archive = Path("talos-sv-0.1.0.dev12-x86_64-pc-windows-msvc.zip")

        def fake_gh(*args):
            calls.append(args)
            if args[:2] == ("api", "--paginate"):
                return json.dumps([[{"tag_name": "dev", "prerelease": True}]])
            if args[:2] == ("release", "view"):
                return json.dumps({"assets": [{"name": name} for name in
                                  [old, old_archive, archive.name, wheels()[0].name,
                                   wheels()[1].name, "unrelated.zip"]]})
            return ""

        with patch("utils.packaging.publish_dev.gh", side_effect=fake_gh):
            publish("owner/repo", "abc123", wheels(), archives=[archive])
        operations = [call[:2] for call in calls]
        self.assertLess(operations.index(("release", "upload")),
                        operations.index(("release", "delete-asset")))
        upload = next(call for call in calls if call[:2] == ("release", "upload"))
        self.assertIn("--clobber", upload)
        self.assertIn(archive, upload)
        deletes = [call[3] for call in calls if call[:2] == ("release", "delete-asset")]
        self.assertEqual(deletes, [old, old_archive])
        edit = next(call for call in calls if call[:2] == ("release", "edit"))
        self.assertIn("--prerelease", edit)
        self.assertIn("--latest=false", edit)

    def test_failed_upload_preserves_previous_assets(self):
        def fake_gh(*args):
            if args[:2] == ("api", "--paginate"):
                return json.dumps([[{"tag_name": "dev", "prerelease": True}]])
            if args[:2] == ("release", "upload"):
                raise subprocess.CalledProcessError(1, "gh release upload")
            self.fail("Release was changed after an upload failure: " + str(args))

        with patch("utils.packaging.publish_dev.gh", side_effect=fake_gh):
            with self.assertRaises(subprocess.CalledProcessError):
                publish("owner/repo", "abc123", wheels())

    def test_missing_archive_prevents_all_remote_changes(self):
        with patch("utils.packaging.publish_dev.gh") as remote:
            with self.assertRaises(ValueError):
                publish("owner/repo", "abc123", wheels(),
                        required_targets=["x86_64-pc-windows-msvc"])
            remote.assert_not_called()

    def test_first_publish_uploads_to_draft_before_publishing(self):
        calls = []

        def fake_gh(*args):
            calls.append(args)
            if args[:2] == ("api", "--paginate"):
                return "[[]]"
            if args[:2] == ("release", "view"):
                return '{"assets": []}'
            return ""

        with patch("utils.packaging.publish_dev.gh", side_effect=fake_gh):
            publish("owner/repo", "abc123", wheels())
        self.assertIn("--draft", calls[1])
        self.assertEqual(calls[2][:2], ("release", "upload"))
        self.assertIn("--draft=false", calls[-1])


if __name__ == "__main__":
    unittest.main()
