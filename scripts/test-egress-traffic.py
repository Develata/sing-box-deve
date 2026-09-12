#!/usr/bin/env python3
"""Local TCP/UDP echo through real cores; no external peers or host services."""
import base64
import contextlib
import importlib.util
import json
import os
from pathlib import Path
import socket
import socketserver
import struct
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import urlencode

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('egress', Path(__file__).with_name('egress-link.py'))
egress = importlib.util.module_from_spec(spec)
spec.loader.exec_module(egress)
UID = '11111111-1111-4111-8111-111111111111'
NO_FLOW_UID = '22222222-2222-4222-8222-222222222222'
HOST = '127.0.0.1'
PAYLOAD = b'sbd-egress-local-echo\x00\xff'


class TCPHandler(socketserver.BaseRequestHandler):
    def handle(self):
        with contextlib.suppress(OSError):
            self.request.settimeout(5)
            while chunk := self.request.recv(4096):
                self.request.sendall(chunk)


class UDPHandler(socketserver.BaseRequestHandler):
    def handle(self):
        data, sock = self.request
        sock.sendto(data, self.client_address)


def port(udp=False):
    with socket.socket(type=socket.SOCK_DGRAM if udp else socket.SOCK_STREAM) as sock:
        sock.bind((HOST, 0))
        return sock.getsockname()[1]


def receive(sock, size):
    result = b''
    while len(result) < size:
        chunk = sock.recv(size - len(result))
        if not chunk:
            raise RuntimeError('Unexpected EOF')
        result += chunk
    return result


def socks_request(sock, command, target_port):
    sock.sendall(b'\x05\x01\x00')
    assert receive(sock, 2) == b'\x05\x00', 'SOCKS authentication failed'
    sock.sendall(bytes([5, command, 0, 1]) + socket.inet_aton(HOST) + struct.pack('!H', target_port))
    header = receive(sock, 4)
    assert header[:2] == b'\x05\x00', 'SOCKS request failed'
    if header[3] == 1:
        address = socket.inet_ntop(socket.AF_INET, receive(sock, 4))
    elif header[3] == 4:
        address = socket.inet_ntop(socket.AF_INET6, receive(sock, 16))
    else:
        address = receive(sock, receive(sock, 1)[0]).decode()
    return address, struct.unpack('!H', receive(sock, 2))[0]


def check_traffic(socks_port, tcp_port, udp_port, udp=True):
    with socket.create_connection((HOST, socks_port), timeout=8) as sock:
        socks_request(sock, 1, tcp_port)
        sock.sendall(PAYLOAD)
        assert receive(sock, len(PAYLOAD)) == PAYLOAD, 'TCP payload mismatch'
    if udp:
        with socket.create_connection((HOST, socks_port), timeout=8) as control, socket.socket(type=socket.SOCK_DGRAM) as sock:
            address, relay_port = socks_request(control, 3, 0)
            sock.settimeout(8)
            packet = b'\x00\x00\x00\x01' + socket.inet_aton(HOST) + struct.pack('!H', udp_port) + PAYLOAD
            sock.sendto(packet, (HOST if address in ('0.0.0.0', '::') else address, relay_port))
            data = sock.recv(4096)
            assert data[:3] == b'\x00\x00\x00' and data.endswith(PAYLOAD), 'UDP payload mismatch'


class Cores:
    def __init__(self, directory):
        self.directory = directory
        self.processes = []

    def start(self, name, command, config=None, ready_port=None):
        if config is not None:
            path = self.directory / (name + '.json')
            path.write_text(json.dumps(config))
            command = [*command, str(path)]
        log = open(self.directory / (name + '.log'), 'w')
        proc = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        self.processes.append((proc, log))
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                raise RuntimeError(name + ' exited: ' + (self.directory / (name + '.log')).read_text())
            # sing-box 1.14 publishes its initial network environment asynchronously
            # after Start. Starting HY2 during that update aborts its first connection.
            # See upstream route/network_environment.go and box.go at v1.14.0.
            output = (self.directory / (name + '.log')).read_text()
            started = config is None or 'loglevel' in config.get('log', {}) or (
                'sing-box started (' in output and (
                    'updated default interface ' not in output or 'updated network environment:' in output))
            if ready_port and started:
                try:
                    with socket.create_connection((HOST, ready_port), timeout=.1):
                        return proc
                except OSError:
                    pass
            elif not ready_port and started and time.monotonic() + 7.5 > deadline:
                return proc
            time.sleep(.05)
        raise RuntimeError(name + ' failed readiness (listener/start/network): ' + (self.directory / (name + '.log')).read_text())

    def close(self):
        for proc, log in reversed(self.processes):
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
            log.close()


def main():
    sb, xr = os.environ.get('SBD_TEST_SINGBOX_BIN'), os.environ.get('SBD_TEST_XRAY_BIN')
    if not sb or not xr:
        print('[SKIP] local egress traffic requires both SBD_TEST_*_BIN paths')
        return
    with tempfile.TemporaryDirectory(prefix='sbd-egress-traffic-') as directory, \
            socketserver.ThreadingTCPServer((HOST, 0), TCPHandler) as tcp, \
            socketserver.ThreadingUDPServer((HOST, 0), UDPHandler) as udp:
        for server in (tcp, udp):
            server.daemon_threads = True
            threading.Thread(target=server.serve_forever, daemon=True).start()
        root = Path(directory)
        cores = Cores(root)
        try:
            cert, key = root / 'cert.pem', root / 'key.pem'
            subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                            '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
                            '-keyout', str(key), '-out', str(cert)], check=True, capture_output=True)
            tls = {'enabled': True, 'server_name': 'localhost', 'certificate_path': str(cert), 'key_path': str(key)}
            reality_keys = subprocess.check_output([sb, 'generate', 'reality-keypair'], text=True)
            keys = dict(line.split(': ', 1) for line in reality_keys.strip().splitlines())
            cover_port = port()
            cores.start('cover', ['openssl', 's_server', '-accept', f'{HOST}:{cover_port}', '-cert', str(cert),
                                 '-key', str(key), '-tls1_3', '-alpn', 'h2', '-quiet', '-www'], ready_port=cover_port)
            cases, inbounds = [], []
            for kind in egress.ENGINE_KINDS['sing-box']:
                remote_port = port(kind == 'hysteria2')
                inbound = {'type': kind, 'listen': HOST, 'listen_port': remote_port}
                query = {'sni': 'localhost', 'insecure': 'true'}
                if kind == 'vless-reality':
                    inbound.update(type='vless', users=[{'uuid': UID, 'flow': 'xtls-rprx-vision'}, {'uuid': NO_FLOW_UID}], tls={
                        'enabled': True, 'server_name': 'localhost', 'reality': {'enabled': True,
                        'private_key': keys['PrivateKey'], 'short_id': ['abcd1234'],
                        'handshake': {'server': HOST, 'server_port': cover_port}}})
                    query = {'security': 'reality', 'sni': 'localhost', 'pbk': keys['PublicKey'], 'sid': 'abcd1234',
                             'flow': 'xtls-rprx-vision'}
                    link = f'vless://{UID}@{HOST}:{remote_port}?{urlencode(query)}'
                elif kind == 'vless-ws':
                    inbound.update(type='vless', users=[{'uuid': UID}], transport={'type': 'ws', 'path': '/ws'})
                    link = f'vless://{UID}@{HOST}:{remote_port}?type=ws&path=%2Fws'
                elif kind == 'hysteria2':
                    inbound.update(users=[{'password': 'local-pass'}], tls=tls,
                                   obfs={'type': 'salamander', 'password': 'local-obfs'})
                    query.update(obfs='salamander', **{'obfs-password': 'local-obfs'})
                    link = f'hy2://local-pass@{HOST}:{remote_port}?{urlencode(query)}'
                elif kind == 'shadowsocks-2022':
                    secret = base64.b64encode(bytes(range(16))).decode()
                    inbound.update(type='shadowsocks', method='2022-blake3-aes-128-gcm', password=secret)
                    auth = base64.urlsafe_b64encode(f'2022-blake3-aes-128-gcm:{secret}'.encode()).decode()
                    link = f'ss://{auth}@{HOST}:{remote_port}'
                else:
                    inbound.update(users=[{'username': 'local-user', 'password': 'local-pass'}], tls=tls, network='tcp')
                    link = f'naive+https://local-user:local-pass@{HOST}:{remote_port}?sni=127.0.0.1'
                inbounds.append(inbound)
                cases.append((kind, link))
                if kind == 'vless-reality':
                    query.pop('flow')
                    cases.append((kind, f'vless://{NO_FLOW_UID}@{HOST}:{remote_port}?{urlencode(query)}'))
                if kind == "naive":
                    cases.append((kind, link + "&uot=true"))
            cores.start('singbox-server', [sb, 'run', '-c'], {'log': {'level': 'info'}, 'inbounds': inbounds,
                         'outbounds': [{'type': 'direct', 'tag': 'direct'}]}, ready_port=inbounds[0]['listen_port'])
            xhttp_port = port()
            project = str(Path(__file__).resolve().parents[1])
            fragment = subprocess.check_output(['bash', '-c',
                'PROJECT_ROOT="$1"; source "$PROJECT_ROOT/lib/load.sh"; shift; xray_fragment_vless_xhttp "$@"',
                'xhttp-fixture', project, UID, str(xhttp_port), 'none', '/xh', 'auto', 'false',
                'localhost', str(cover_port), keys['PrivateKey'], 'abcd1234'], text=True)
            inbound = json.loads(fragment)
            inbound['listen'] = HOST
            cores.start('xray-server', [xr, 'run', '-c'], {'log': {'loglevel': 'error'},
                'inbounds': [inbound], 'outbounds': [{'protocol': 'freedom'}]}, ready_port=xhttp_port)
            link = subprocess.check_output(['bash', '-c',
                'PROJECT_ROOT="$1"; source "$PROJECT_ROOT/lib/load.sh"; shift; node_link_vless_xhttp "$@"',
                'xhttp-link-fixture', project, UID, HOST, str(xhttp_port), 'none', 'localhost', 'chrome',
                keys['PublicKey'], 'abcd1234', '%2Fxh', 'auto', '', 'none'], text=True).strip()
            cases.append(('vless-xhttp', link))
            for engine, binary in (('sing-box', sb), ('xray', xr)):
                for kind, link in cases:
                    if kind not in egress.ENGINE_KINDS[engine]:
                        continue
                    name = engine + '-' + kind + ('-uot' if 'uot=true' in link else '')
                    if NO_FLOW_UID in link:
                        name += '-no-flow'
                    local_port = port()
                    node = egress.parse_link(link)
                    if engine == 'xray':
                        node['insecure'] = False
                    if engine == 'sing-box':
                        outbound = egress.render_singbox(node)
                        if kind == 'naive':
                            # Test CA only; production links still require normal verified TLS.
                            outbound['tls']['certificate_path'] = str(cert)
                        config = {'log': {'level': 'info'}, 'inbounds': [{'type': 'socks', 'listen': HOST,
                                  'listen_port': local_port}], 'outbounds': [outbound], 'route': {'final': 'proxy-out'}}
                    else:
                        config = {'log': {'loglevel': 'error'}, 'inbounds': [{'protocol': 'socks', 'listen': HOST,
                                  'port': local_port, 'settings': {'udp': True}}], 'outbounds': [egress.render_xray(node)]}
                        if kind == 'hysteria2':
                            config['outbounds'][0]['streamSettings']['tlsSettings']['certificates'] = [
                                {'certificateFile': str(cert), 'usage': 'verify'}]
                    proc = cores.start(name, [binary, 'run', '-c'], config, ready_port=local_port)
                    try:
                        check_traffic(local_port, tcp.server_address[1], udp.server_address[1], node['udp'])
                    except Exception as error:
                        logs = '\n'.join(p.read_text()[-5000:] for p in root.glob('*.log'))
                        raise RuntimeError(f'{name}: {error}\n{logs}') from error
                    proc.terminate()
                    proc.wait(timeout=3)
                    print(f'[OK] {name}: TCP' + (' + UDP' if node['udp'] else ''), flush=True)
        finally:
            cores.close()
            tcp.shutdown()
            udp.shutdown()


if __name__ == '__main__':
    main()
