#!/usr/bin/env python3
"""Calcule un code TOTP (RFC 6238, HMAC-SHA1, 30 s, 6 chiffres) à partir d'un secret base32.

Utilisé par la recette (scripts/recette.sh) pour simuler l'application d'authentification
d'un prestataire, sans dépendance externe. Usage : totp.py SECRET_BASE32 [décalage_en_secondes]
Le décalage permet de démontrer le piège de l'horloge : au-delà de ±30 s, le code est refusé.
"""
import base64, hashlib, hmac, struct, sys, time

secret = sys.argv[1].strip().upper()
offset = int(sys.argv[2]) if len(sys.argv) > 2 else 0
key = base64.b32decode(secret + "=" * (-len(secret) % 8))
counter = int((time.time() + offset) // 30)
digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
pos = digest[-1] & 0x0F
code = (struct.unpack(">I", digest[pos:pos + 4])[0] & 0x7FFFFFFF) % 1_000_000
print(f"{code:06d}")
