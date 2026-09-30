#!/usr/bin/env python3
"""Revalidacion de la autenticacion LDAPS de ERPNext e InvenTree en el arnes de un host, contra Samba AD DC.

Adaptado de OpenLDAP a Samba AD DC (rama feat/samba-ad-dc). Pendiente de verificar contra el arnes real:
se ejecuta por primera vez en la Fase 2 (una vez dev tenga `samba-ad` arriba con la siembra completa).
Endpoints, credenciales y codigos de respuesta HTTP heredados de la version OpenLDAP salieron de
docs/prueba-smoke-test-resultados.md §9.3 (retirado; `git show 95e0da4:docs/prueba-smoke-test-resultados.md`).

Requisito: el sistema ya levantado (`levantar-sistema.sh arrancar`, o `docker compose --env-file sistema/test.env up -d`
desde la raiz del repositorio) y con las apps sanas.
Uso (desde esta carpeta):
    python ldaplogin.py                      # casos 1-3 sobre el stack en marcha
    python ldaplogin.py --persistencia       # ademas, caso 4: down (sin -v) + up -d y repite 1-3
Sale con codigo 0 solo si todos los casos ejecutados dan PASS.

Casos:
  1. Login con usuario LDAP correcto        -> 200 (ERPNext) / 200 + token (InvenTree)
  2. Contrasena erronea                     -> rechazo (401/403; ERPNext devuelve 417)
  3. ldapsearch por LDAPS con la CA         -> OK con verificacion completa (nombre ldap.reservaviva.lan);
                                               y FALLA con una CA ajena por "peer cert untrusted"
  4. Persistencia tras down sin -v + up -d  -> los casos 1-3 dan el mismo resultado
Las peticiones HTTP se hacen con `docker exec` DENTRO de los contenedores de las apps (con macvlan/bridge
el host no alcanza esas IP). El ldapsearch (caso 3) se ejecuta con `docker exec` DENTRO de `samba-ad`: es
quien tiene montada la CA del proyecto en /certs/ca.crt y resuelve ldap.reservaviva.lan con su propio DNS
(forwarder hacia bind9 para lo que no es su propia zona AD). Hay que ejecutarlo donde `docker` sea el
cliente nativo (p. ej. dentro de WSL): `docker` como .cmd no lo resuelve subprocess sin shell.
"""
import argparse, json, os, subprocess, sys, time
from pathlib import Path

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parent   # donde esta docker-compose.yml
ENV_FILE = RAIZ / "sistema" / "test.env"
# El caso 4 llama a compose desde la raiz y con el fichero de variables: sin --env-file fallarian las variables ":?".
COMPOSE = ["docker", "compose", "--env-file", "sistema/test.env"]
SITE = "rrhh.reservaviva.local"   # nombre del SITIO de ERPNext (identificador interno), no el nombre DNS (.lan)
BASE = "DC=ad,DC=reservaviva,DC=lan"
DOMINIO_UPN = "ad.reservaviva.lan"      # sufijo UPN: usuario@ad.reservaviva.lan
CA_EN_SAMBA_AD = "/certs/ca.crt"


def valor_env(clave):
    """Lee una variable de sistema/test.env sin ejecutarlo, como valor_env() de levantar-sistema.sh (gana la ultima)."""
    valor = ""
    for linea in ENV_FILE.read_text(encoding="utf-8").splitlines():
        if linea.startswith(clave + "="):
            valor = linea.split("=", 1)[1].rstrip("\r")
    if not valor:
        sys.exit(f"Falta {clave}: definir {clave} en sistema/test.env")
    return valor


# Claves de los usuarios de prueba: sistema/test.env es su unica fuente (la siembra de samba-ad los crea con
# ellas). Nunca van en la linea de comandos: se pasan por la variable de entorno CLAVE_LDAP.
ERP_USER, ERP_PASS = "rrhh.prueba", valor_env("LDAP_PRUEBA_RRHH_PASSWORD")
INV_USER, INV_PASS = "logistica.prueba", valor_env("LDAP_PRUEBA_LOGISTICA_PASSWORD")
MALA = "clave-incorrecta-xyz"
# Nombre real del despliegue (pc2: INVENTREE_LDAP_SERVER_URI) y presente en el SAN del certificado.
# NO usar ldaps://localhost: libldap canonicaliza el nombre al hostname del contenedor (p. ej.
# 4f89b94c57b9), que no esta en el SAN, y la verificacion falla aunque LDAPS funcione (ver
# docs/prueba-smoke-test-resultados.md, ejecucion de 2026-09-20; retirado, ver git show 95e0da4).
LDAP_URI = "ldaps://ldap.reservaviva.lan:636"

# Se ejecuta dentro del contenedor: imprime "<status> <cuerpo recortado>". Sin dependencias externas.
HTTP_ERP = r"""
import os, sys, urllib.request, urllib.parse, urllib.error
u, site = sys.argv[1:3]
p = os.environ["CLAVE_LDAP"]
req = urllib.request.Request(
    "http://127.0.0.1:8000/api/method/frappe.integrations.doctype.ldap_settings.ldap_settings.login",
    data=urllib.parse.urlencode({"usr": u, "pwd": p}).encode(), headers={"Host": site})
try:
    r = urllib.request.urlopen(req, timeout=30); print(r.status, r.read()[:200].decode("utf8", "replace"))
except urllib.error.HTTPError as e:
    print(e.code, e.read()[:200].decode("utf8", "replace"))
except Exception as e:
    # Timeout, conexion cortada...: una linea legible en vez de un traceback que se recorta a 200 caracteres.
    print("None", type(e).__name__ + ":", e)
"""
HTTP_INV = r"""
import os, sys, base64, urllib.request, urllib.error
u = sys.argv[1]
p = os.environ["CLAVE_LDAP"]
tok = base64.b64encode((u + ":" + p).encode()).decode()
req = urllib.request.Request("http://127.0.0.1:8000/api/user/token/", headers={"Authorization": "Basic " + tok})
try:
    r = urllib.request.urlopen(req, timeout=30); print(r.status, r.read()[:200].decode("utf8", "replace"))
except urllib.error.HTTPError as e:
    print(e.code, e.read()[:200].decode("utf8", "replace"))
except Exception as e:
    # Timeout, conexion cortada...: una linea legible en vez de un traceback que se recorta a 200 caracteres.
    print("None", type(e).__name__ + ":", e)
"""


def sh(cmd, entrada=None, timeout=1500, cwd=AQUI, clave=None):
    """clave: se pasa como variable de entorno CLAVE_LDAP (docker exec/run -e CLAVE_LDAP la hereda), nunca en argv."""
    env = None if clave is None else {**os.environ, "CLAVE_LDAP": clave}
    return subprocess.run(cmd, input=entrada, capture_output=True, text=True, timeout=timeout, cwd=cwd, env=env)


def http(contenedor, script, clave, *args):
    """Devuelve (status:int|None, texto). None = no se pudo ejecutar."""
    r = sh(["docker", "exec", "-i", "-e", "CLAVE_LDAP", contenedor, "python3", "-", *args], entrada=script, clave=clave)
    salida = r.stdout.strip()
    if r.returncode != 0 or not salida.split(" ", 1)[0].isdigit():
        return None, (r.stderr or salida).strip()[:200]
    cod, _, resto = salida.partition(" ")
    return int(cod), resto


def ldapsearch(usuario, clave, ca="real"):
    """ca='real': CA del laboratorio (debe verificar). ca='ajena': una CA valida pero que no firmo el
    certificado (debe fallar por 'peer cert untrusted', no por nombre ni por fichero ilegible).
    Bind por UPN (usuario@ad.reservaviva.lan): robusto frente al CN real, que --use-username-as-cn deja
    igual al uid al sembrar pero no conviene asumir aqui. Se ejecuta con `docker exec` DENTRO de
    samba-ad: tiene montada la CA del proyecto en /certs/ca.crt (igual que los demas consumidores) y
    resuelve ldap.reservaviva.lan con su propio DNS (dns forwarder hacia bind9 para lo que no es su
    zona AD), sin necesitar --network/--dns/--volumes-from de un contenedor efimero aparte."""
    upn = f"{usuario}@{DOMINIO_UPN}"
    if ca == "real":
        pre = f"export LDAPTLS_CACERT={CA_EN_SAMBA_AD}"
    else:
        pre = ("openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null -out /tmp/ajena.crt "
               "-subj /CN=CA-ajena -days 1 >/dev/null 2>&1; export LDAPTLS_CACERT=/tmp/ajena.crt")
    cmd = ["docker", "exec", "-i", "-e", "CLAVE_LDAP", "samba-ad", "sh", "-c",
           f'{pre}; umask 077; printf %s "$CLAVE_LDAP" >/tmp/clave; exec ldapsearch "$@"', "_",
           "-x", "-LLL", "-d1", "-H", LDAP_URI, "-D", upn, "-y", "/tmp/clave",
           "-b", BASE, "-s", "sub", f"(sAMAccountName={usuario})", "sAMAccountName"]
    r = sh(cmd, timeout=120, clave=clave)
    salida = r.stdout + r.stderr
    # -d1 es muy verboso: se conservan las lineas utiles (resultado LDAP y errores TLS).
    utiles = [l for l in salida.splitlines() if l.startswith(("sAMAccountName:", "dn:", "TLS:", "ldap_bind", "ldap_sasl_bind"))]
    return r.returncode, " | ".join(utiles)


def caso1():
    res = []
    s, t = http("erpnext-backend", HTTP_ERP, ERP_PASS, ERP_USER, SITE)
    res.append((f"ERPNext {ERP_USER}", s == 200, f"status={s} {t[:80]}"))
    s, t = http("inventree-app", HTTP_INV, INV_PASS, INV_USER)
    res.append((f"InvenTree {INV_USER}", s == 200 and "token" in t, f"status={s} {t[:80]}"))
    return res


def caso2():
    res = []
    s, t = http("erpnext-backend", HTTP_ERP, MALA, ERP_USER, SITE)
    res.append(("ERPNext clave erronea", s in (401, 403, 417), f"status={s} (esperado 401/403/417)"))
    s, t = http("inventree-app", HTTP_INV, MALA, INV_USER)
    res.append(("InvenTree clave erronea", s in (401, 403), f"status={s} (esperado 401/403)"))
    return res


def caso3():
    res = []
    rc, out = ldapsearch(ERP_USER, ERP_PASS)
    res.append(("ldapsearch con CA (rrhh.prueba)", rc == 0 and f"sAMAccountName: {ERP_USER}" in out, f"rc={rc} {out[-80:]}"))
    rc, out = ldapsearch(INV_USER, INV_PASS)
    res.append(("ldapsearch con CA (logistica.prueba)", rc == 0 and f"sAMAccountName: {INV_USER}" in out, f"rc={rc} {out[-80:]}"))
    rc, out = ldapsearch(ERP_USER, MALA)
    res.append(("ldapsearch clave erronea", rc == 49, f"rc={rc} (esperado 49 Invalid credentials)"))
    rc, out = ldapsearch(ERP_USER, ERP_PASS, ca="ajena")
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


def esperar_apps(limite=600):
    fin = time.time() + limite
    while time.time() < fin:
        s1, _ = http("erpnext-backend", HTTP_ERP, MALA, ERP_USER, SITE)
        s2, _ = http("inventree-app", HTTP_INV, MALA, INV_USER)
        if s1 is not None and s2 is not None and s1 != 404:
            break
        time.sleep(15)
    else:
        return False
    # Responder a la clave erronea no basta: el primer login correcto de ERPNext tras `up -d` (abre la
    # conexion LDAP y crea la sesion) puede agotar los 30 s con gunicorn aun en frio (H18). Se reintenta
    # el login correcto, dentro del mismo limite, hasta que devuelva 200.
    while time.time() < fin:
        s, t = http("erpnext-backend", HTTP_ERP, ERP_PASS, ERP_USER, SITE)
        if s == 200:
            return True
        print(f"  ERPNext aun no acepta el login correcto: status={s} {t[:80]}")
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
        for cmd in (COMPOSE + ["down"], COMPOSE + ["up", "-d"]):
            r = sh(cmd, cwd=RAIZ)
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
