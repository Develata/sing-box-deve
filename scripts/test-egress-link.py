#!/usr/bin/env python3
"""Protocol import, capability and credential-boundary regression checks."""
import base64
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest
from urllib.parse import quote

sys.dont_write_bytecode = True
SCRIPT = Path(__file__).with_name('egress-link.py')
spec = importlib.util.spec_from_file_location('egress_link', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
UID = '11111111-1111-4111-8111-111111111111'
KEY = base64.urlsafe_b64encode(bytes(range(32))).decode().rstrip('=')
REALITY = f'vless://{UID}@exit.example:443?security=reality&pbk={KEY}&sid=abcd&sni=cover.example&fp=chrome'


class Links(unittest.TestCase):
    def test_reality_and_ipv6(self):
        node = module.parse_link(REALITY.replace('exit.example', '[2001:db8::1]'))
        self.assertEqual(node['server'], '2001:db8::1')
        for render in (module.render_singbox, module.render_xray):
            out = render(node)
            self.assertEqual(out['tag'], 'proxy-out')
        out = module.render_singbox(node)
        self.assertEqual(out['tls']['reality']['public_key'], KEY)
        self.assertNotIn('domain_resolver', out)

    def test_round_trip_encoded_credentials(self):
        password = 'user:p@ss & " \\ $() `echo nope` + 中文'
        node = module.parse_link(f'hy2://{quote(password, safe="")}@exit.example?sni=cover.example&obfs=salamander&obfs-password=obfs%26pass')
        self.assertEqual(node['password'], password)
        self.assertEqual(node['port'], 443)
        self.assertEqual(module.render_singbox(node)['obfs']['password'], 'obfs&pass')
        xr = module.render_xray(node)
        self.assertEqual(xr['streamSettings']['hysteriaSettings']['auth'], password)
        self.assertEqual(xr['streamSettings']['finalmask']['udp'][0]['type'], 'salamander')

    def test_websocket_tls(self):
        node = module.parse_link(f'vless://{UID}@exit.example:8443?type=ws&security=tls&path=%2Fa%3Fed%3D2048&host=cdn.example&sni=cdn.example')
        out = module.render_singbox(node)
        self.assertEqual(out['transport']['path'], '/a?ed=2048')
        self.assertEqual(out['transport']['headers']['Host'], 'cdn.example')
        self.assertEqual(out['tls']['server_name'], 'cdn.example')
        self.assertEqual(out['domain_resolver'], 'dns-local')

    def test_core_capabilities(self):
        tuic = module.parse_link(f'tuic://{UID}:password@exit.example?congestion_control=cubic&udp_relay_mode=quic')
        self.assertEqual(module.render_singbox(tuic)['udp_relay_mode'], 'quic')
        with self.assertRaises(module.LinkError):
            module.render_xray(tuic)
        naive = module.parse_link('naive+https://user:password@exit.example?uot=true')
        self.assertTrue(module.render_singbox(naive)['udp_over_tcp'])
        self.assertNotIn('insecure', module.render_singbox(naive)['tls'])
        with self.assertRaises(module.LinkError):
            module.render_xray(naive)
        xhttp = module.parse_link(REALITY + '&type=xhttp&path=%2Fstream&mode=auto')
        self.assertEqual(module.render_xray(xhttp)['streamSettings']['network'], 'xhttp')
        with self.assertRaises(module.LinkError):
            module.render_singbox(xhttp)

    def test_rejected_core_tls_and_xhttp_flow(self):
        node = module.parse_link('hy2://password@exit.example?insecure=true')
        self.assertTrue(module.render_singbox(node)['tls']['insecure'])
        with self.assertRaises(module.LinkError):
            module.render_xray(node)
        with self.assertRaises(module.LinkError):
            module.parse_link(f'vless://{UID}@exit.example?type=xhttp&flow=xtls-rprx-vision')

    def test_reality_flow_is_not_invented(self):
        for suffix, expected in (('', ''), ('&flow=', ''), ('&flow=xtls-rprx-vision', 'xtls-rprx-vision')):
            node = module.parse_link(REALITY + suffix)
            self.assertEqual(module.render_singbox(node).get('flow', ''), expected)
            self.assertEqual(module.render_xray(node)['settings']['vnext'][0]['users'][0].get('flow', ''), expected)

    def test_reality_export_compatibility(self):
        canonical = REALITY + '&type=tcp&flow=xtls-rprx-vision&encryption=none'
        expected = module.parse_link(canonical)
        for name in ('insecure', 'allowInsecure', 'allow_insecure'):
            for value in ('1', 'true', '0', 'false'):
                with self.subTest(name=name, value=value):
                    node = module.parse_link(canonical + f'&{name}={value}&udp=1')
                    self.assertFalse(node['insecure'])
                    self.assertTrue(node['udp'])
                    for render in (module.render_singbox, module.render_xray):
                        self.assertEqual(render(node), render(expected))
        # The same normalization applies to the Xray Reality/XHTTP transport.
        node = module.parse_link(REALITY + '&type=xhttp&allowInsecure=1&udp=1')
        self.assertFalse(node['insecure'])
        self.assertEqual(module.render_xray(node)['streamSettings']['security'], 'reality')

    def test_vless_udp_export_flag(self):
        for value, expected in (('0', False), ('false', False), ('1', True), ('true', True)):
            self.assertIs(module.parse_link(REALITY + '&udp=' + value)['udp'], expected)
        for suffix in ('&udp=maybe', '&udp=1&udp=0', '&allowInsecure=maybe',
                       '&insecure=1&allowInsecure=1'):
            with self.subTest(suffix=suffix), self.assertRaises(module.LinkError):
                module.parse_link(REALITY + suffix)

    def test_udp_export_flags_across_protocols(self):
        password = base64.b64encode(bytes(range(16))).decode()
        auth = base64.urlsafe_b64encode(('2022-blake3-aes-128-gcm:' + password).encode()).decode().rstrip('=')
        links = (REALITY, f'vless://{UID}@exit.example?type=ws',
                 'hysteria2://password@exit.example?sni=exit.example',
                 f'tuic://{UID}:password@exit.example?congestion_control=bbr',
                 f'ss://{auth}@exit.example:443?',
                 'naive+https://user:password@exit.example?uot=true')
        for link in links:
            canonical = module.parse_link(link)
            for value, expected in (('0', False), ('false', False), ('1', True), ('true', True)):
                with self.subTest(kind=canonical['kind'], value=value):
                    node = module.parse_link(link + '&udp=' + value)
                    self.assertIs(node['udp'], expected)
                    for engine, render in (('sing-box', module.render_singbox), ('xray', module.render_xray)):
                        if node['kind'] in module.ENGINE_KINDS[engine]:
                            out = render(node)
                            if node['kind'] == 'naive':
                                self.assertEqual(out.get('udp_over_tcp', False), expected)
                            else:
                                self.assertEqual(out, render(canonical))
            for suffix in ('&udp=maybe', '&udp=', '&udp=1&udp=0'):
                with self.subTest(kind=canonical['kind'], suffix=suffix), self.assertRaises(module.LinkError):
                    module.parse_link(link + suffix)

    def test_naive_udp_flag_does_not_enable_uot(self):
        for query in ('udp=1', 'uot=false&udp=true', 'uot=0&udp=1'):
            node = module.parse_link('naive+https://user:password@exit.example?' + query)
            self.assertFalse(node['udp'])
            self.assertNotIn('udp_over_tcp', module.render_singbox(node))

    def test_userinfo_delimiters_precede_decoding(self):
        for link in ('naive+https://user%3Apass@exit.example',
                     'naive+https://user%3Aname:pass@exit.example',
                     f'tuic://{UID}%3Apass@exit.example'):
            with self.subTest(link=link), self.assertRaises(module.LinkError):
                module.parse_link(link)
        node = module.parse_link('naive+https://local%40user:local%3Apass%40word@exit.example')
        self.assertEqual(node['username'], 'local@user')
        self.assertEqual(node['password'], 'local:pass@word')

    def test_shadowsocks_formats(self):
        password = base64.b64encode(bytes(range(16))).decode()
        auth = '2022-blake3-aes-128-gcm:' + password
        modern = base64.urlsafe_b64encode(auth.encode()).decode().rstrip('=')
        legacy = base64.b64encode((auth + '@exit.example:8443').encode()).decode()
        for link in (f'ss://{modern}@exit.example:8443', f'ss://{quote(auth, safe="")}@exit.example:8443', f'ss://{legacy}'):
            node = module.parse_link(link)
            self.assertEqual(module.render_singbox(node)['password'], password)
            self.assertEqual(module.render_xray(node)['settings']['servers'][0]['password'], password)

    def test_invalid_links_are_rejected(self):
        invalid = [
            '', REALITY + '&pbk=duplicate', REALITY.replace(':443?', ':0?'),
            REALITY.replace(':443?', ':65536?'), REALITY.replace('sid=abcd', 'sid=abc'),
            REALITY.replace(KEY, 'bad'), REALITY.replace(UID, 'invalid-uuid'),
            REALITY + '&unexpected=value', REALITY + '&insecure=maybe',
            REALITY + '&type=grpc', REALITY + '&type=ws', REALITY + '&sni=other',
            'hy2://pass%00word@exit.example', 'hy2://bad%GG@exit.example',
            'hy2://password@exit.example?insecure=maybe',
            'hy2://password@exit.example?obfs=salamander',
            'hy2://password@exit.example?obfs=gecko',
            'tuic://bad:password@exit.example', 'tuic://' + UID + '@exit.example',
            'naive+https://user:pass@exit.example?insecure=true',
            'ss://2022-blake3-aes-128-gcm:bad@exit.example:443',
        ]
        for link in invalid:
            with self.subTest(index=invalid.index(link)), self.assertRaises((module.LinkError, ValueError)):
                module.parse_link(link)

    def test_cli_errors_do_not_echo_credentials(self):
        for link in ('hy2://private-secret@[not-an-ip]:443', 'hy2://private-secret@exit.example:bad',
                     'hy2://private-secret%FF@exit.example', 'hy2://private-secret@exit.example?unknown=1'):
            result = subprocess.run([sys.executable, str(SCRIPT), 'info'], input=link, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('private-secret', result.stdout + result.stderr)
            self.assertNotIn('Traceback', result.stderr)

    def test_file_input_and_bounds(self):
        result = subprocess.run([sys.executable, str(SCRIPT), 'info'], input=REALITY + '\n', capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)['kind'], 'vless-reality')
        for link in (REALITY + '\n' * module.LIMIT, REALITY + '\n' + REALITY):
            result = subprocess.run([sys.executable, str(SCRIPT), 'link'], input=link, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')


if __name__ == '__main__':
    unittest.main()
