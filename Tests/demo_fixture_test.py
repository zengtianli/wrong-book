"""Exercise actual localhost HTTP fixtures; no real accounts, transport or simulator."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import urllib.error
import urllib.request

spec = importlib.util.spec_from_file_location("demo_fixture", Path(__file__).resolve().parents[1] / "scripts/demo/fixture.py")
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class FixtureIsolation(unittest.TestCase):
    def test_cookie_isolation_and_anonymous_login_capture(self):
        with tempfile.TemporaryDirectory(prefix="wrongbook-fixture-test.") as root:
            dirs = [Path(root) / name for name in ("first", "second", "anonymous")]
            try:
                first, second, anonymous = [fixture.start(p, i == 2) for i, p in enumerate(dirs)]
                request = urllib.request.Request(first["url"] + "/api/login", data=json.dumps({"u": first["user"], "p": first["pw"]}).encode())
                with urllib.request.urlopen(request) as response:
                    cookie = response.headers["Set-Cookie"].split(";", 1)[0]
                request = urllib.request.Request(first["url"] + "/api/state", headers={"Cookie": cookie})
                with urllib.request.urlopen(request) as response:
                    self.assertEqual(json.load(response)["u"], fixture.USER)
                for target in (second, anonymous):
                    with self.assertRaises(urllib.error.HTTPError) as failure:
                        urllib.request.urlopen(urllib.request.Request(target["url"] + "/api/state", headers={"Cookie": cookie}))
                    self.assertEqual(failure.exception.code, 401)
                for endpoint in ("login", "phone_send", "email_send"):
                    request = urllib.request.Request(anonymous["url"] + "/api/" + endpoint, data=b"{}")
                    with self.assertRaises(urllib.error.HTTPError) as failure:
                        urllib.request.urlopen(request)
                    self.assertEqual(failure.exception.code, 503)
            finally:
                for path in dirs:
                    fixture.stop(path)


if __name__ == "__main__":
    unittest.main()
