"""Isolated SMS transport fixture; never imports an SMS SDK or reads owner phones.

Production HTTP/auth/challenge/storage and the actual native App remain in use.
These originals cannot establish sms_transport=real or sms_delivery.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import secrets
import threading


class PhoneFixture:
    numbers = ('13800000000', '13900000000', '13700000000')

    def __init__(self):
        self.requests = {}
        self.token = secrets.token_hex(32)
        self.server = self.worker = self.module = self.original = None
        self.sends = self.verifications = 0

    def send(self, phone, purpose, out_id):
        if phone.removeprefix('+86') not in self.numbers:
            raise RuntimeError('Fixture refuses non-fixture recipient')
        self.requests[out_id] = (phone, purpose, str(secrets.randbelow(1000000)).zfill(6))
        self.sends += 1
        return {'status': 'fixture_only', 'request_id': 'fixture', 'biz_id': out_id}

    def check(self, phone, purpose, out_id, code):
        passed = self.requests.get(out_id) == (phone, purpose, code)
        if passed: self.verifications += 1
        return passed

    def install(self):
        import account_phone
        self.module, self.original = account_phone, account_phone.gateway
        fixture = self
        class Coordinator(BaseHTTPRequestHandler):
            def do_POST(self):
                try:
                    if self.path != '/receive' or self.headers.get('X-WrongBook-QA') != fixture.token:
                        raise ValueError()
                    size = int(self.headers.get('Content-Length', '0'))
                    if not 0 < size <= 1024: raise ValueError()
                    body = json.loads(self.rfile.read(size))
                    phone, _, code = fixture.requests[body['challenge']]
                    if body['phone'] != phone.removeprefix('+86'): raise ValueError()
                    data = json.dumps({'code': code}).encode()
                    self.send_response(200); self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)
                except Exception:
                    self.send_response(403); self.send_header('Content-Length', '0'); self.end_headers()
            def log_message(self, *_): pass
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Coordinator)
        self.worker = threading.Thread(target=self.server.serve_forever, daemon=True); self.worker.start()
        account_phone.gateway = lambda: self
        return dict(zip(('phone_a', 'phone_b', 'phone_c'), self.numbers), phone_token=self.token,
                    phone_coordinator='http://127.0.0.1:' + str(self.server.server_port),
                    phone_recovered=secrets.token_urlsafe(24))

    def close(self):
        if self.module is not None: self.module.gateway = self.original
        if self.server is not None: self.server.shutdown(); self.server.server_close()
        if self.worker is not None: self.worker.join(timeout=3)
        self.requests.clear()
