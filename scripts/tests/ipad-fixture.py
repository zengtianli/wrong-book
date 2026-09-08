"""Local-only layout fixture; no real accounts, lessons, or backend writes.

Run python3 scripts/tests/ipad-fixture.py, then launch a Debug simulator build:
  -api_base http://127.0.0.1:18880 -learn.openLesson ipad-layout
This exercises normal account restore, manifest/hash validation, and LessonWebView.
"""
import hashlib
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlsplit

PAGE = '''<!doctype html><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>body{font:20px system-ui;padding:24px;color:#172033;background:#fff}
button{font:inherit;padding:12px;margin:8px}</style>
<h1>iPad 布局测试</h1><p>仅本机合成课程，用于验证列表与练习并排。</p>
<p>2 + 3 = ?</p><button onclick="this.textContent='回答正确：5'">5</button>
'''.encode()


class Fixture(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path
        responses = {
            '/api/state': dict(ok=True, u='ipad-fixture', nick='布局测试'),
            '/api/account_delete_request': dict(ok=True, status='none'),
            '/api/lessons': dict(owner='ipad-fixture', scope='ipad-fixture-v1', lessons=[
                dict(slug='ipad-layout', title='iPad 布局测试', desc='仅本机合成资料',
                     file='ipad-layout.html', subject='math', subject_name='数学',
                     unit='测试课程', sha256=hashlib.sha256(PAGE).hexdigest())]),
        }
        if path == '/api/lesson':
            data, content_type = PAGE, 'text/html; charset=utf-8'
        elif path in responses:
            data = json.dumps(responses[path]).encode()
            content_type = 'application/json'
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == '__main__':
    HTTPServer(('127.0.0.1', 18880), Fixture).serve_forever()
