"""Read GymCount release state using the local ASC key; never print credentials."""
import base64
import json
import shlex
import time
import urllib.request
from pathlib import Path
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature


def request(path, body=None, method=None):
    values = {}
    for line in (Path.home() / '.appstoreconnect/assettimemachine.env').read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.removeprefix('export ').split('=', 1)
            values[key.strip()] = shlex.split(value)[0]
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value, separators=(',', ':')).encode()).rstrip(b'=')
    now = int(time.time())
    signing_input = encode({'alg': 'ES256', 'kid': values['ASC_KEY_ID'], 'typ': 'JWT'}) + b'.' + encode({'iss': values['ASC_ISSUER_ID'], 'iat': now, 'exp': now + 600, 'aud': 'appstoreconnect-v1'})
    key = serialization.load_pem_private_key(Path(values['ASC_KEY_PATH']).expanduser().read_bytes(), password=None)
    r, s = decode_dss_signature(key.sign(signing_input, ec.ECDSA(hashes.SHA256())))
    token = signing_input + b'.' + base64.urlsafe_b64encode(r.to_bytes(32, 'big') + s.to_bytes(32, 'big')).rstrip(b'=')
    req = urllib.request.Request('https://api.appstoreconnect.apple.com/v1/' + path,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={'Authorization': 'Bearer ' + token.decode(), 'Content-Type': 'application/json'}, method=method)
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response) if response.status != 204 else {}


if __name__ == '__main__':
    apps = request('apps?filter[bundleId]=com.flyingrtx.GymCount')['data']
    for app in apps:
        print('APP', app['id'], app['attributes']['name'])
        for build in request('builds?filter[app]=' + app['id'] + '&sort=-uploadedDate&limit=5&include=preReleaseVersion')['data']:
            print('BUILD', build['id'], json.dumps(build['attributes'], ensure_ascii=False))
        for group in request('apps/' + app['id'] + '/betaGroups')['data']:
            print('GROUP', group['id'], group['attributes']['name'], group['attributes'].get('isInternalGroup'))
