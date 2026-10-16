"""Read-only real IMAP receiver and bounded real SMTP transport for WrongBook QA.

Imports no other product's runner or stopped send contract. Credentials stay in
memory; only recipient/message hashes and delivery counts enter raw evidence.
"""
from contextlib import contextmanager
from email import message_from_bytes
from email.policy import default
from email.utils import getaddresses
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import imaplib
import json
from pathlib import Path
import re
import secrets
import subprocess
import threading
import time


def configuration():
    code = '''from pathlib import Path
import json,shlex
p=Path('/etc/edu-points-mail.env')
if p.stat().st_mode & 0o077: raise SystemExit(2)
d={}
for line in p.read_text().splitlines():
 if '=' in line and not line.lstrip().startswith('#'):
  k,v=line.split('=',1)
  if k.startswith('EDU_SMTP_'): d[k]=shlex.split(v)[0] if v else ''
print(json.dumps(d))
'''
    result = subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', 'vps', 'python3', '-'],
                            input=code, capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise RuntimeError('Existing protected SMTP configuration is unavailable')
    cfg = json.loads(result.stdout)
    if not all(cfg.get(key) for key in ('EDU_SMTP_HOST', 'EDU_SMTP_USER', 'EDU_SMTP_PASSWORD', 'EDU_SMTP_FROM')):
        raise RuntimeError('Existing SMTP configuration is incomplete')
    if cfg['EDU_SMTP_USER'].split('@')[0] != 'hi':
        raise RuntimeError('Transport account differs from the existing owner mailbox')
    return cfg


def received_code(data, address):
    message = message_from_bytes(data, policy=default)
    recipient_headers = [str(message[name]) for name in ('To', 'Delivered-To', 'X-Original-To') if message.get(name)]
    recipients = {value.lower() for _, value in getaddresses(recipient_headers)}
    if address.lower() not in recipients:
        return None
    parts = message.walk() if message.is_multipart() else [message]
    body = '\n'.join(part.get_content() for part in parts if part.get_content_type() == 'text/plain')
    hit = re.search(r'验证码[：:\s]+(\d{6})', body)
    return (hit.group(1), hashlib.sha256(str(message.get('Message-ID', '')).encode()).hexdigest()) if hit else None


class RealMail:
    def __init__(self, directory, write):
        self.directory, self.write = directory, write
        self.cfg = configuration()
        domain = self.cfg['EDU_SMTP_USER'].split('@', 1)[1]
        suffix = secrets.token_hex(6)
        self.addresses = ['hi+wrongbook-native-' + suffix + '-' + key + '@' + domain for key in 'abcd']
        self.allowed = set(self.addresses)
        self.attempts = self.accepted = 0
        self.events, self.pending = [], {}
        self.token = secrets.token_hex(32)
        self.server = self.worker = self.original = self.security = None
        self.lock = threading.RLock()
        # Budget belongs only to this product, including uncertain sends from
        # previous live attempts. Never borrow the stopped PointsDeck contract.
        self.prior = sum(json.loads(path.read_text()).get('smtp_attempts', 0)
                         for path in directory.parent.glob('native-*/mail-transport.json'))
        if self.prior >= 20:
            raise RuntimeError('WrongBook real-mail budget exhausted; do not resend')

    @contextmanager
    def mailbox(self):
        mailbox = None
        try:
            mailbox = imaplib.IMAP4_SSL(self.cfg['EDU_SMTP_HOST'], 993, timeout=15)
            mailbox.login(self.cfg['EDU_SMTP_USER'], self.cfg['EDU_SMTP_PASSWORD'])
            status, _ = mailbox.select('INBOX', readonly=True)
            if status != 'OK': raise RuntimeError()
        except Exception:
            if mailbox is not None:
                try: mailbox.logout()
                except Exception: pass
            raise RuntimeError('Existing read-only mailbox is unavailable') from None
        try: yield mailbox
        finally:
            try: mailbox.logout()
            except Exception: pass

    def latest(self):
        with self.mailbox() as mailbox:
            status, rows = mailbox.uid('search', None, 'ALL')
            if status != 'OK': raise RuntimeError('Mailbox UID baseline unavailable')
            return max(map(int, rows[0].split()), default=0)

    def record(self):
        self.write(self.directory / 'mail-transport.json', {'smtp_attempts': self.attempts, 'smtp_accepted': self.accepted,
            'budget': 20, 'prior_attempts': self.prior, 'events': self.events,
            'scope': 'Real SMTP and read-only IMAP, owner mailbox plus aliases only; no codes or credentials retained'})

    def install(self):
        import account_security
        self.security, self.original = account_security, account_security.send_mail
        original = self.original
        def send(address, subject, text):
            with self.lock:
                if address not in self.allowed or self.attempts + self.prior >= 20:
                    raise account_security.Fault('WrongBook test recipient/budget guard', 503)
                try: baseline = self.latest() if '验证码' in subject else None
                except Exception:
                    raise account_security.Fault('Read-only mail receiver unavailable; no message sent', 503) from None
                self.attempts += 1; self.record()
                original(address, subject, text)
                self.accepted += 1
                if baseline is not None: self.pending[address] = baseline
                self.events.append({'kind': 'smtp_accepted', 'recipient_sha256': hashlib.sha256(address.encode()).hexdigest(),
                                    'message_kind': 'code' if baseline is not None else 'notification'})
                self.record()
        account_security.send_mail = send
        receiver = self
        class Coordinator(BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def do_POST(self):
                try:
                    if self.path != '/receive' or self.headers.get('X-WrongBook-QA') != receiver.token:
                        raise PermissionError()
                    length = int(self.headers.get('Content-Length', '0'))
                    if not 0 < length < 4096: raise ValueError()
                    address = json.loads(self.rfile.read(length))['email']
                    code = receiver.wait_code(address)
                    reply, status = {'code': code}, 200
                except Exception:
                    reply, status = {'error': 'Real-mail receipt unavailable; no resend performed'}, 503
                payload = json.dumps(reply).encode()
                self.send_response(status); self.send_header('Content-Length', str(len(payload))); self.end_headers()
                self.wfile.write(payload)
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Coordinator)
        self.worker = threading.Thread(target=self.server.serve_forever, daemon=True); self.worker.start()
        return {**dict(zip(('mail_a', 'mail_b', 'mail_c', 'mail_d'), self.addresses)),
                'coordinator': 'http://127.0.0.1:' + str(self.server.server_port), 'coordinator_token': self.token,
                'recovered': secrets.token_urlsafe(28)}

    def wait_code(self, address):
        if address not in self.allowed or address not in self.pending:
            raise PermissionError('No authorized pending message')
        baseline = self.pending[address]
        deadline = time.monotonic() + 85
        while time.monotonic() < deadline:
            with self.mailbox() as mailbox:
                status, rows = mailbox.uid('search', None, 'UID', str(baseline + 1) + ':*')
                if status != 'OK': raise RuntimeError('Mailbox search failed')
                for uid in reversed(rows[0].split()):
                    if int(uid) <= baseline: continue
                    status, data = mailbox.uid('fetch', uid, '(BODY.PEEK[])')
                    if status != 'OK': continue
                    source = next((part[1] for part in data if isinstance(part, tuple)), None)
                    found = received_code(source, address) if source else None
                    if found:
                        code, message_sha = found
                        with self.lock:
                            self.events.append({'kind': 'imap_received', 'recipient_sha256': hashlib.sha256(address.encode()).hexdigest(),
                                                'uid_sha256': hashlib.sha256(uid).hexdigest(), 'message_id_sha256': message_sha})
                            del self.pending[address]; self.record()
                        return code
            time.sleep(2)
        raise TimeoutError('Actual mail was not received within the bounded window')

    def complete(self):
        received = [event for event in self.events if event['kind'] == 'imap_received']
        return self.accepted >= 6 and len(received) >= 6 and len({e['recipient_sha256'] for e in received}) == 4

    def close(self):
        if self.server: self.server.shutdown(); self.server.server_close()
        if self.worker: self.worker.join(timeout=3)
        if self.security is not None: self.security.send_mail = self.original
