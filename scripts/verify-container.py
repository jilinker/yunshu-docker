"""Exercise a real SOCKS5 domain request against a disposable local HTTP server."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import socket
import struct
import threading


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'yunshu-socks-smoke-ok\n'
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def read_exact(sock, size):
    data = b''
    while len(data) < size:
        part = sock.recv(size - len(data))
        if not part:
            raise RuntimeError('Unexpected EOF from SOCKS5')
        data += part
    return data


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with socket.create_connection(('127.0.0.1', 7171), timeout=5) as sock:
        sock.sendall(b'\x05\x01\x00')
        assert read_exact(sock, 2) == b'\x05\x00', 'SOCKS5 negotiation failed'
        domain = b'localhost'
        sock.sendall(b'\x05\x01\x00\x03' + bytes([len(domain)]) + domain
                     + struct.pack('!H', server.server_port))
        reply = read_exact(sock, 4)
        assert reply[:3] == b'\x05\x00\x00', f'CONNECT failed: {reply!r}'
        if reply[3] == 1:
            read_exact(sock, 4)
        elif reply[3] == 4:
            read_exact(sock, 16)
        elif reply[3] == 3:
            read_exact(sock, read_exact(sock, 1)[0])
        else:
            raise AssertionError(f'Invalid reply address: {reply[3]}')
        read_exact(sock, 2)
        sock.sendall(b'GET / HTTP/1.0\r\nHost: localhost\r\n\r\n')
        response = b''
        while chunk := sock.recv(4096):
            response += chunk
        assert b'200 OK' in response and response.endswith(b'yunshu-socks-smoke-ok\n')
    print('PASS: SOCKS5 negotiation, domain CONNECT, HTTP request and response')
finally:
    server.shutdown()
    server.server_close()
