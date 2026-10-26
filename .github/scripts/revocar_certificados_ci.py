"""Revoca los certificados de desarrollo que dejaron compilaciones anteriores.

Cada compilación en GitHub Actions crea un certificado "Apple Development"
cuya llave privada se pierde al terminar (el Mac es efímero). La siguiente
compilación en una máquina "igual" falla con "Revoke certificate: ... its
private key is not installed". Antes de firmar se revocan los certificados de
desarrollo creados por la API (displayName "Created via API"); nunca los de
distribución. Lista todos en el registro para poder revisarlos.

Uso: python revocar_certificados_ci.py <ruta .p8>   (ASC_KEY_ID y ASC_ISSUER_ID en el entorno)
"""
import json
import os
import sys
import time
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
TIPOS_DESARROLLO = {"DEVELOPMENT", "IOS_DEVELOPMENT"}


def token(key_path: str) -> str:
    ahora = int(time.time())
    with open(key_path, encoding="utf-8") as f:
        clave = f.read()
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": ahora, "exp": ahora + 600, "aud": "appstoreconnect-v1"},
        clave,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def pedir(metodo: str, url: str, tok: str):
    req = urllib.request.Request(url, method=metodo, headers={"Authorization": f"Bearer {tok}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        cuerpo = r.read()
    return json.loads(cuerpo) if cuerpo else None


def main() -> int:
    tok = token(sys.argv[1])
    datos = pedir("GET", f"{API}/certificates?limit=200", tok)["data"]
    revocados = 0
    for c in datos:
        a = c["attributes"]
        tipo, nombre = a.get("certificateType"), a.get("displayName") or ""
        print(f"- {tipo} | {nombre} | {a.get('name')} | vence {a.get('expirationDate')}")
        if tipo in TIPOS_DESARROLLO and "via api" in nombre.lower():
            pedir("DELETE", f"{API}/certificates/{c['id']}", tok)
            revocados += 1
            print(f"  revocado {c['id']}")
    print(f"Certificados de desarrollo de la integración revocados: {revocados}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
