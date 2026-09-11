#!/usr/bin/env python3
"""Parse one share link and render a core outbound; never execute link content."""
import base64
import ipaddress
import json
import re
import sys
import uuid
from urllib.parse import parse_qsl, unquote, urlsplit

LIMIT = 16384
LINK_SCHEMES = {'vless': 'vless', 'hy2': 'hysteria2', 'hysteria2': 'hysteria2',
                'ss': 'shadowsocks-2022', 'naive+https': 'naive'}
ENGINE_KINDS = {
    'sing-box': ['vless-reality', 'vless-ws', 'hysteria2', 'shadowsocks-2022', 'naive'],
    'xray': ['vless-reality', 'vless-ws', 'vless-xhttp', 'hysteria2', 'shadowsocks-2022'],
}


class LinkError(ValueError):
    pass


def require(ok, message):
    if not ok:
        raise LinkError(message)


def clean(value, field, required=False):
    require(isinstance(value, str) and not any(ord(c) < 32 or ord(c) == 127 for c in value),
            f"Invalid {field}")
    require(not required or bool(value), f"Missing {field}")
    return value


def decode64(value, field):
    try:
        return base64.b64decode(value + '=' * (-len(value) % 4), altchars=b'-_', validate=True)
    except (ValueError, UnicodeError):
        raise LinkError(f"Invalid base64 {field}") from None


def boolean(value, field):
    require(value.lower() in ('0', '1', 'false', 'true'), f"Invalid {field}")
    return value.lower() in ('1', 'true')


def user_id(value):
    try:
        return str(uuid.UUID(value))
    except ValueError:
        raise LinkError('Invalid UUID') from None


def parse_link(link):
    require(0 < len(link.encode()) <= LIMIT, 'Empty or oversized node link')
    require(not any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in link),
            'Encode spaces and control characters in the node link')
    require(not re.search(r'%(?![0-9a-fA-F]{2})', link), 'Invalid percent encoding')
    parts = urlsplit(link)
    scheme = parts.scheme.lower()
    require(scheme != 'tuic', 'TUIC is no longer supported')
    require(scheme in LINK_SCHEMES,
            'Supported links: vless://, hy2://, hysteria2://, ss://, naive+https://')
    # Legacy SIP002 encodes the entire authority; modern links encode userinfo.
    if scheme == 'ss' and '@' not in parts.netloc:
        authority = decode64(parts.netloc, 'Shadowsocks authority').decode('utf-8')
        parts = urlsplit('ss://' + authority + ('?' + parts.query if parts.query else ''))
    require(parts.path in ('', '/'), 'Transport paths must use the path query parameter')
    host = clean(parts.hostname or '', 'server', True)
    require(not any(c in host for c in '/\\@?#') and not any(c.isspace() for c in host), 'Invalid server')
    if ':' in host:
        try:
            ipaddress.IPv6Address(host)
        except ValueError:
            raise LinkError('Invalid IPv6 server') from None
    port = parts.port if parts.port is not None else 443
    require(1 <= port <= 65535, 'Server port must be between 1 and 65535')
    require('@' in parts.netloc, 'Missing node credentials')
    credentials = clean(unquote(parts.netloc.rsplit('@', 1)[0], errors='strict'), 'credentials', True)
    params = {}
    for key, value in parse_qsl(parts.query, keep_blank_values=True, errors='strict', max_num_fields=48):
        require(key not in params, 'Duplicate node parameter')
        params[clean(key, 'parameter name')] = clean(value, 'parameter value')

    def take(name, default='', aliases=()):
        present = [key for key in (name, *aliases) if key in params]
        require(len(present) <= 1, f'Conflicting {name} parameters')
        return params.pop(present[0]) if present else default

    udp_enabled = boolean(take('udp', 'true'), 'UDP')
    node = {'server': host, 'port': port, 'udp': True}
    if scheme != 'ss':
        node['sni'] = clean(take('sni', host, ('peer', 'serverName')), 'SNI', True)
        require(not any(c.isspace() for c in node['sni']), 'Invalid SNI')
        node['insecure'] = boolean(take('insecure', 'false', ('allowInsecure', 'allow_insecure')), 'insecure')
        node['alpn'] = [clean(v, 'ALPN', True) for v in take('alpn').split(',') if v]
    if scheme == 'vless':
        require(':' not in credentials, 'VLESS credentials must contain only a UUID')
        node['uuid'] = user_id(credentials)
        node['security'] = take('security', 'none')
        transport = take('type', 'tcp', ('network',))
        if transport == 'raw':
            transport = 'tcp'
        require(transport in ('tcp', 'ws', 'xhttp'), 'Unsupported VLESS transport')
        require(node['security'] in ('none', 'tls', 'reality'), 'Unsupported VLESS security')
        require(transport != 'tcp' or node['security'] == 'reality', 'VLESS TCP egress requires Reality')
        require(transport != 'ws' or node['security'] != 'reality', 'Reality over WebSocket is unsupported')
        node['kind'] = 'vless-reality' if transport == 'tcp' else 'vless-' + transport
        node['encryption'] = take('encryption', 'none')
        require(bool(node['encryption']) and not any(c.isspace() for c in node['encryption']), 'Invalid VLESS encryption')
        node['flow'] = take('flow')
        require(node['flow'] in ('', 'xtls-rprx-vision'), 'Unsupported VLESS flow')
        require(transport != 'ws' or not node['flow'], 'WebSocket does not support Vision flow')
        require(transport != 'xhttp' or not node['flow'] or node['encryption'] != 'none',
                'XHTTP Vision requires VLESS encryption; regenerate incompatible old links')
        node['fingerprint'] = take('fp', 'chrome')
        if node['security'] == 'reality':
            # Some exporters attach a generic TLS flag to Reality links. Keep
            # Reality authentication enabled rather than passing that flag on.
            node['insecure'] = False
            node['public_key'] = take('pbk')
            require(len(decode64(node['public_key'], 'Reality public key')) == 32, 'Reality public key must contain 32 bytes')
            node['short_id'] = take('sid')
            require(bool(re.fullmatch(r'(?:[0-9a-fA-F]{2}){0,8}', node['short_id'])), 'Invalid Reality short ID')
        if transport in ('ws', 'xhttp'):
            node['path'] = take('path', '/')
            require(node['path'].startswith('/'), 'Transport path must start with /')
            node['host'] = take('host')
        if transport == 'xhttp':
            node['xhttp_mode'] = take('mode', 'auto')
            require(node['xhttp_mode'] in ('auto', 'packet-up', 'stream-up', 'stream-one'), 'Invalid XHTTP mode')
        require(take('packetEncoding', 'xudp') == 'xudp', 'Only XUDP packet encoding is supported')
    elif scheme in ('hy2', 'hysteria2'):
        node.update(kind='hysteria2', password=credentials)
        require(take('security', 'tls') == 'tls', 'Hysteria2 requires TLS')
        node['obfs'] = take('obfs', 'off') or 'off'
        require(node['obfs'] in ('off', 'salamander'), 'Supported Hysteria2 obfs: salamander')
        if node['obfs'] != 'off':
            node['obfs_password'] = clean(take('obfs-password', aliases=('obfsPassword',)), 'obfs password', True)
    elif scheme == 'ss':
        if ':' not in credentials:
            credentials = decode64(credentials, 'Shadowsocks credentials').decode('utf-8')
        method, sep, password = credentials.partition(':')
        sizes = {'2022-blake3-aes-128-gcm': 16, '2022-blake3-aes-256-gcm': 32,
                 '2022-blake3-chacha20-poly1305': 32}
        require(bool(sep) and method in sizes, 'Only Shadowsocks-2022 links are supported')
        require(all(len(decode64(key, 'Shadowsocks key')) == sizes[method] for key in password.split(':')),
                'Invalid Shadowsocks-2022 key length')
        node.update(kind='shadowsocks-2022', method=method, password=password)
    else:
        require(parts.password is not None, 'Naive link requires username:password')
        username = unquote(parts.username or '', errors='strict')
        password = unquote(parts.password, errors='strict')
        require(':' not in username, 'Naive Basic auth username cannot contain a colon')
        node.update(kind='naive', username=clean(username, 'username', True), password=clean(password, 'password', True))
        require(not node['insecure'] and not node['alpn'], 'Naive requires verified TLS and does not accept ALPN overrides')
        node['udp'] = boolean(take('uot', 'false'), 'Naive uot')
    # Export metadata can disable UDP, but cannot grant transport capability.
    node['udp'] = node['udp'] and udp_enabled
    require(not params, 'Unsupported node link parameter (remove unsupported options instead of silently ignoring them)')
    return node


def tls_singbox(node):
    tls = {'enabled': True, 'server_name': node['sni']}
    if node['kind'] != 'naive':
        tls['insecure'] = node['insecure']
        if node['alpn']:
            tls['alpn'] = node['alpn']
    if node.get('fingerprint'):
        tls['utls'] = {'enabled': True, 'fingerprint': node['fingerprint']}
    if node.get('security') == 'reality':
        tls['reality'] = {'enabled': True, 'public_key': node['public_key'], 'short_id': node['short_id']}
    return tls


def render_singbox(node):
    kind = node['kind']
    require(kind in ENGINE_KINDS['sing-box'], 'VLESS-XHTTP egress requires the Xray engine')
    require(node.get('encryption', 'none') == 'none', 'VLESS encryption egress requires the Xray engine')
    out = {'type': 'vless' if kind.startswith('vless-') else 'shadowsocks' if kind == 'shadowsocks-2022' else kind,
           'tag': 'proxy-out', 'server': node['server'], 'server_port': node['port']}
    try:
        ipaddress.ip_address(node['server'])
    except ValueError:
        out['domain_resolver'] = 'dns-local'
    for field in ('uuid', 'password', 'username', 'method'):
        if field in node:
            out[field] = node[field]
    if kind == 'vless-reality':
        out['flow'] = node['flow']
    if kind == 'vless-ws':
        out['transport'] = {'type': 'ws', 'path': node['path']}
        if node['host']:
            out['transport']['headers'] = {'Host': node['host']}
    if kind != 'shadowsocks-2022' and node.get('security', 'tls') != 'none':
        out['tls'] = tls_singbox(node)
    if node.get('obfs', 'off') != 'off':
        out['obfs'] = {'type': node['obfs'], 'password': node['obfs_password']}
    if kind == 'naive' and node['udp']:
        out['udp_over_tcp'] = True
    return out


def render_xray(node):
    kind = node['kind']
    require(kind in ENGINE_KINDS['xray'], f'{kind} egress requires the sing-box engine')
    out = {'tag': 'proxy-out'}
    if kind == 'shadowsocks-2022':
        out.update(protocol='shadowsocks', settings={'servers': [{
            'address': node['server'], 'port': node['port'], 'method': node['method'], 'password': node['password']}]})
        return out
    security = node.get('security', 'tls')
    stream = {'network': 'hysteria' if kind == 'hysteria2' else 'tcp', 'security': security}
    if security == 'reality':
        stream['realitySettings'] = {'serverName': node['sni'], 'fingerprint': node['fingerprint'],
                                     'publicKey': node['public_key'], 'shortId': node['short_id']}
    elif security == 'tls':
        require(not node['insecure'], 'Current Xray requires verified TLS; insecure links are unsupported')
        stream['tlsSettings'] = {'serverName': node['sni']}
        if node.get('fingerprint'):
            stream['tlsSettings']['fingerprint'] = node['fingerprint']
        if node['alpn']:
            stream['tlsSettings']['alpn'] = node['alpn']
    if kind == 'hysteria2':
        out.update(protocol='hysteria', settings={'version': 2, 'address': node['server'], 'port': node['port']})
        stream['hysteriaSettings'] = {'version': 2, 'auth': node['password']}
        stream['tlsSettings'].setdefault('alpn', ['h3'])
        if node['obfs'] != 'off':
            stream['finalmask'] = {'udp': [{'type': 'salamander', 'settings': {'password': node['obfs_password']}}]}
    else:
        user = {'id': node['uuid'], 'encryption': node['encryption']}
        if kind in ('vless-reality', 'vless-xhttp'):
            user['flow'] = node['flow']
        out.update(protocol='vless', settings={'vnext': [{'address': node['server'], 'port': node['port'], 'users': [user]}]})
        if kind == 'vless-ws':
            stream['network'] = 'ws'
            stream['wsSettings'] = {'path': node['path']}
            if node['host']:
                stream['wsSettings']['headers'] = {'Host': node['host']}
        elif kind == 'vless-xhttp':
            stream['network'] = 'xhttp'
            stream['xhttpSettings'] = {'path': node['path'], 'mode': node['xhttp_mode']}
            if node['host']:
                stream['xhttpSettings']['host'] = node['host']
    out['streamSettings'] = stream
    return out


def main():
    if sys.argv[1:] == ['capabilities']:
        print(json.dumps({'schemes': LINK_SCHEMES, 'engines': ENGINE_KINDS}))
        return
    require(len(sys.argv) == 2 and sys.argv[1] in ('info', 'sing-box', 'xray', 'link'), 'Expected info, sing-box or xray')
    raw = sys.stdin.read(LIMIT + 1)
    require(len(raw.encode()) <= LIMIT, 'Oversized node link input')
    link = raw.rstrip('\r\n')
    node = parse_link(link)
    command = sys.argv[1]
    if command == 'link':
        print(link)
        return
    if command == 'info':
        result = {key: node[key] for key in ('kind', 'server', 'port', 'udp')}
    else:
        result = render_singbox(node) if command == 'sing-box' else render_xray(node)
    print(json.dumps(result, ensure_ascii=True, separators=(',', ':')))


if __name__ == '__main__':
    try:
        main()
    except LinkError as error:
        print(f'[ERROR] {error}', file=sys.stderr)
        sys.exit(2)
    except (ValueError, UnicodeError):
        # urllib/base64 exceptions can contain credentials: never echo them.
        print('[ERROR] Invalid node link encoding, address or port', file=sys.stderr)
        sys.exit(2)
