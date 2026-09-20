#!/usr/bin/env python3
"""Revalidacion de la autenticacion LDAPS de ERPNext e InvenTree en el arnes de un host.

NO VERIFICADO: escrito sin poder ejecutarlo (Docker no estaba disponible). Endpoints, credenciales y
codigos de respuesta salen de docs/prueba-smoke-test-resultados.md §9.3, no de una ejecucion de este script.

Requisito: el arnes ya levantado (`docker compose up -d` en esta carpeta) y con las apps sanas.
Uso (desde esta carpeta):
    python ldaplogin.py                      # casos 1-3 sobre el stack en marcha
    python ldaplogin.py --persistencia       # ademas, caso 4: down (sin -v) + up -d y repite 1-3
Sale con codigo 0 solo si todos los casos ejecutados dan PASS.

Casos:
  1. Login con usuario LDAP correcto        -> 200 (ERPNext) / 200 + token (InvenTree)
  2. Contrasena erronea                     -> rechazo (401/403; ERPNext devuelve 417)
  3. ldapsearch por LDAPS con la CA         -> OK con verificacion completa (nombre ldap.reservaviva.local);
                                               y FALLA con una CA ajena por "peer cert untrusted"
  4. Persistencia tras down sin -v + up -d  -> los casos 1-3 dan el mismo resultado
Las peticiones HTTP se hacen con `docker exec` DENTRO de los contenedores de las apps (con macvlan/bridge
el host no alcanza esas IP). El ldapsearch corre en un contenedor efimero (imagen de openldap) unido a la
red del arnes y con el DNS del laboratorio (dns-interno). Hay que ejecutarlo donde `docker` sea el cliente
nativo (p. ej. dentro de WSL): `docker` como .cmd no lo resuelve subprocess sin shell.
"""
import argparse, json, subprocess, sys, time
from pathlib import Path

AQUI = Path(__file__).resolve().parent
SITE = "rrhh.reservaviva.local"
BASE = "dc=reservaviva,dc=local"
CA_EN_OPENLDAP = "/container/service/slapd/assets/certs/ca.crt"
# Claves de laboratorio: docker/pc3-administracion-infra/ldap/README.md
ERP_USER, ERP_PASS, ERP_OU = "rrhh.prueba", "Rrhh-Prueba1", "rrhh"
INV_USER, INV_PASS, INV_OU = "logistica.prueba", "Oper-Prueba1", "operaciones"
MALA = "clave-incorrecta-xyz"
# Nombre real del despliegue (pc2: INVENTREE_LDAP_SERVER_URI) y presente en el SAN del certificado.
# NO usar ldaps://localhost: libldap canonicaliza el nombre al hostname del contenedor (p. ej.
# 4f89b94c57b9), que no esta en el SAN, y la verificacion falla aunque LDAPS funcione (ver
# docs/prueba-smoke-test-resultados.md, ejecucion de 2026-09-20).
LDAP_URI = "ldaps://ldap.reservaviva.local:636"

# Se ejecuta dentro del contenedor: imprime "<status> <cuerpo recortado>". Sin dependencias externas.
HTTP_ERP = r"""
import sys, urllib.request, urllib.parse, urllib.error
u, p, site = sys.argv[1:4]
req = urllib.request.Request(
    "http://127.0.0.1:8000/api/method/frappe.integrations.doctype.ldap_settings.ldap_settings.login",
    data=urllib.parse.urlencode({"usr": u, "pwd": p}).encode(), headers={"Host": site})
try:
    r = urllib.request.urlopen(req, timeout=30); print(r.status, r.read()[:200].decode("utf8", "replace"))
except urllib.error.HTTPError as e:
    print(e.code, e.read()[:200].decode("utf8", "replace"))
"""
HTTP_INV = r"""
import sys, base64, urllib.request, urllib.error
u, p = sys.argv[1:3]
tok = base64.b64encode((u + ":" + p).encode()).decode()
req = urllib.request.Request("http://127.0.0.1:8000/api/user/token/", headers={"Authorization": "Basic " + tok})
try:
    r = urllib.request.urlopen(req, timeout=30); print(r.status, r.read()[:200].decode("utf8", "replace"))
except urllib.error.HTTPError as e:
    print(e.code, e.read()[:200].decode("utf8", "replace"))
"""


def sh(cmd, entrada=None, timeout=1500):
    return subprocess.run(cmd, input=entrada, capture_output=True, text=True, timeout=timeout, cwd=AQUI)


def http(contenedor, script, *args):
    """Devuelve (status:int|None, texto). None = no se pudo ejecutar."""
    r = sh(["docker", "exec", "-i", contenedor, "python3", "-", *args], entrada=script)
    salida = r.stdout.strip()
    if r.returncode != 0 or not salida.split(" ", 1)[0].isdigit():
        return None, (r.stderr or salida).strip()[:200]
    cod, _, resto = salida.partition(" ")
    return int(cod), resto


def _inspeccionar(contenedor, plantilla):
    return sh(["docker", "inspect", contenedor, "--format", plantilla], timeout=30).stdout.strip()


def ldapsearch(usuario, ou, clave, ca="real"):
    """ca='real': CA del laboratorio (debe verificar). ca='ajena': una CA valida pero que no firmo el
    certificado (debe fallar por 'peer cert untrusted', no por nombre ni por fichero ilegible)."""
    dn = f"uid={usuario},ou={ou},{BASE}"
    imagen = _inspeccionar("openldap", "{{.Config.Image}}")
    red = _inspeccionar("openldap", "{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}").split()[0]
    dns = _inspeccionar("dns-interno", "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}")
    if ca == "real":
        pre = f"export LDAPTLS_CACERT={CA_EN_OPENLDAP}"
    else:
        pre = ("openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null -out /tmp/ajena.crt "
               "-subj /CN=CA-ajena -days 1 >/dev/null 2>&1; export LDAPTLS_CACERT=/tmp/ajena.crt")
    # Contenedor efimero con el DNS del laboratorio: ldap.reservaviva.local se resuelve como en produccion.
    # --volumes-from openldap aporta el volumen de certificados (ca.crt).
    cmd = ["docker", "run", "--rm", "--network", red, "--dns", dns, "--volumes-from", "openldap",
           "--entrypoint", "", "-e", "LDAPTLS_REQCERT=demand", imagen, "sh", "-c",
           f'{pre}; exec ldapsearch "$@"', "_", "-x", "-LLL", "-d1", "-H", LDAP_URI, "-D", dn, "-w", clave,
           "-b", dn, "-s", "base", "uid"]
    r = sh(cmd, timeout=120)
    salida = r.stdout + r.stderr
    # -d1 es muy verboso: se conservan las lineas utiles (resultado LDAP y errores TLS).
    utiles = [l for l in salida.splitlines() if l.startswith(("uid:", "dn:", "TLS:", "ldap_bind", "ldap_sasl_bind"))]
    return r.returncode, " | ".join(utiles)


def caso1():
    res = []
    s, t = http("erpnext-backend", HTTP_ERP, ERP_USER, ERP_PASS, SITE)
    res.append((f"ERPNext {ERP_USER}", s == 200, f"status={s} {t[:80]}"))
    s, t = http("inventree-app", HTTP_INV, INV_USER, INV_PASS)
    res.append((f"InvenTree {INV_USER}", s == 200 and "token" in t, f"status={s} {t[:80]}"))
    return res


def caso2():
    res = []
    s, t = http("erpnext-backend", HTTP_ERP, ERP_USER, MALA, SITE)
    res.append(("ERPNext clave erronea", s in (401, 403, 417), f"status={s} (esperado 401/403/417)"))
    s, t = http("inventree-app", HTTP_INV, INV_USER, MALA)
    res.append(("InvenTree clave erronea", s in (401, 403), f"status={s} (esperado 401/403)"))
    return res


def caso3():
    res = []
    rc, out = ldapsearch(ERP_USER, ERP_OU, ERP_PASS)
    res.append(("ldapsearch con CA (rrhh.prueba)", rc == 0 and f"uid: {ERP_USER}" in out, f"rc={rc} {out[-80:]}"))
    rc, out = ldapsearch(INV_USER, INV_OU, INV_PASS)
    res.append(("ldapsearch con CA (logistica.prueba)", rc == 0 and f"uid: {INV_USER}" in out, f"rc={rc} {out[-80:]}"))
    rc, out = ldapsearch(ERP_USER, ERP_OU, MALA)
    res.append(("ldapsearch clave erronea", rc == 49, f"rc={rc} (esperado 49 Invalid credentials)"))
    rc, out = ldapsearch(ERP_USER, ERP_OU, ERP_PASS, ca="ajena")
    res.append(("ldapsearch con CA ajena debe fallar por certificado no confiable",
                rc != 0 and "untrusted" in out, f"rc={rc} {out[-100:]}"))
    return res


def ejecutar(titulo, fn):
    print(f"\n== {titulo}")
    res = fn()
    for nombre, ok, detalle in res:
        print(f"  [{'PASS' if ok else 'FAIL'}] {nombre}: {detalle}")
    todo = all(ok for _, ok, _ in res)
    print(f"  => {titulo}: {'PASS' if todo else 'FAIL'}")
    return todo


def esperar_apps(limite=1500):
    fin = time.time() + limite
    while time.time() < fin:
        s1, _ = http("erpnext-backend", HTTP_ERP, ERP_USER, MALA, SITE)
        s2, _ = http("inventree-app", HTTP_INV, INV_USER, MALA)
        if s1 is not None and s2 is not None and s1 != 404:
            return True
        time.sleep(15)
    return False


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--persistencia", action="store_true", help="caso 4: down sin -v + up -d y repetir 1-3")
    a = ap.parse_args()
    ok = [ejecutar("Caso 1: login LDAP correcto", caso1),
          ejecutar("Caso 2: contrasena erronea", caso2),
          ejecutar("Caso 3: ldapsearch LDAPS con CA", caso3)]
    if a.persistencia:
        print("\n== Caso 4: docker compose down (SIN -v) + up -d")
        for cmd in (["docker", "compose", "down"], ["docker", "compose", "up", "-d"]):
            r = sh(cmd)
            print(f"  {' '.join(cmd)} -> rc={r.returncode}")
            if r.returncode != 0:
                print(r.stderr[-400:]); ok.append(False); break
        else:
            if not esperar_apps():
                print("  las apps no respondieron a tiempo"); ok.append(False)
            else:
                ok += [ejecutar("Caso 4a: login correcto tras reinicio", caso1),
                       ejecutar("Caso 4b: contrasena erronea tras reinicio", caso2),
                       ejecutar("Caso 4c: ldapsearch tras reinicio", caso3)]
    print("\nVEREDICTO GLOBAL:", "PASS" if all(ok) else "FAIL")
    return 0 if all(ok) else 1


if __name__ == "__main__":
    sys.exit(main())
