# Dev: checks a channel's update.sig against its update.txt with FlameKit's release public key, the same check the DLL
# makes (web_update.hpp, signed_by_release_key) before anything is taken. Run before every publish.
# Usage: python3 tools/check_sig.py <channel folder, e.g. dist-test> [<list> <signature>]
#   (0.15.454) EMF's channel: python3 tools/check_sig.py emf-dist-test emf.txt emf.sig
import sys
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature
from cryptography.exceptions import InvalidSignature

# BCRYPT_ECCPUBLIC_BLOB: "ECS1", 32, X (32 bytes), Y (32 bytes): the same bytes as kReleaseKey in web_update.hpp
BLOB = bytes.fromhex("4543533120000000e2a6cbc89239baf4d9facbd2ab33c2fc77cc7019e4e6b161ebb3d385a989b734550e16aa8ecfb66d4319072c0a082f1ffa22a022707ae5f023147eb3970cf6a6")
key = ec.EllipticCurvePublicNumbers(int.from_bytes(BLOB[8:40], "big"), int.from_bytes(BLOB[40:72], "big"), ec.SECP256R1()).public_key()

channel = sys.argv[1]
list_name, sig_name = (sys.argv[2], sys.argv[3]) if len(sys.argv) == 4 else ("update.txt", "update.sig")
data = open(f"{channel}/{list_name}", "rb").read()
sig = bytes.fromhex(open(f"{channel}/{sig_name}").read().strip())
assert len(sig) == 64, "the signature is not 64 bytes"
der = encode_dss_signature(int.from_bytes(sig[:32], "big"), int.from_bytes(sig[32:], "big"))  # Windows writes r||s
try:
    key.verify(der, data, ec.ECDSA(hashes.SHA256()))
    print(f"{channel}: {sig_name} is good ({data.split(b'\n', 1)[0].decode()})")
except InvalidSignature:
    sys.exit(f"{channel}: {sig_name} does NOT match {list_name}")
