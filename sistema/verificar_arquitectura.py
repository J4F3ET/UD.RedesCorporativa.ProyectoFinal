#!/usr/bin/env python3
"""Verificacion de que la ARQUITECTURA (no solo los contenedores) se comporta como esta disenada, en un host.

El sistema se publica en UNA IP (HOST_IP) y un puerto por servicio; los contenedores comparten una sola red. Este
guion comprueba que cada servicio esta abierto donde debe (desde el anfitrion y desde un contenedor), que las bases de
datos y Redis no se publican, y que DNS, NTP, el proxy web y el directorio (Samba AD) funcionan por esos puertos.

El ultimo resultado contra el sistema completo esta en docs/resultados-un-host.md. `--autotest` prueba la mecanica
(cliente DNS por UDP y TCP, cliente SNTP, lector de zona, lectura de PortBindings) contra sockets locales, sin tocar
Docker. Ver verificar_arquitectura.md para el alcance y sus limites.

Requisito: el sistema levantado (`levantar-sistema.sh arrancar`) y sano. Ejecutar donde `docker` sea el cliente
nativo (p. ej. dentro de WSL), igual que ldaplogin.py. Sin dependencias fuera de la libreria estandar.
HOST_IP se toma del entorno (el lanzador lo exporta, y `--ip` lo sobrescribe) o, si falta, de sistema/test.env; se
contrasta con la IP en la que Docker publica proxy-web.

Uso (desde esta carpeta):
    python3 verificar_arquitectura.py                     # todos los bloques, incluido ldaplogin.py --persistencia
    python3 verificar_arquitectura.py --sin-persistencia  # sin el caso 4 (que hace down + up -d y tarda)
    python3 verificar_arquitectura.py --informe out.txt   # ademas guarda la salida completa
    python3 verificar_arquitectura.py --autotest          # solo la mecanica, sin Docker

Bloques: 1 puertos (una IP, un puerto por servicio; BD y Redis sin publicar) | 2 DNS (bind9 consultado de verdad) |
3 NTP | 4 acceso por nombre (proxy web con HTML + estatico, acceso directo por HOST_IP y por localhost) |
5 Active Directory (SRV de _ldap/_kerberos via bind9, kinit/klist, grupos, prueba negativa de membresia) |
6 consolidacion (ldapprobe.py, probe.py, ldaplogin.py, sin duplicarlos).
Cada comprobacion da PASS / FAIL / INFO con la salida literal en la que se apoya. Sale con 0 SOLO si no hay ningun FAIL.
INFO no cuenta: son hallazgos que hay que leer, no fallos del guion.

Por que un fallo tiene que ocurrir por la razon correcta: un puerto cerrado y un destino mudo dan resultados parecidos.
Los negativos (BD y Redis no alcanzables en HOST_IP) solo cuentan como PASS si (a) el anfitrion prueba que HOST_IP es
alcanzable (control del origen: el proxy contesta) y (b) el servicio SI escucha dentro de la red, por su nombre (control
del destino). Sin esos dos controles un puerto cerrado no prueba nada y se marca FAIL.
"""
import argparse, errno, http.client, json, os, re, socket, ssl, struct, subprocess, sys, threading, time
from urllib.parse import urljoin
from pathlib import Path

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parent
DOMINIO = "reservaviva.lan"
ZONA = RAIZ / "servicios/bind9/zones/db.reservaviva.lan"   # unica zona (todos los nombres -> HOST_IP, mas la delegacion ad)
CA_CRT = RAIZ / "servicios/ca/certs/ca.crt"
ENV_FILE = AQUI / "test.env"
ETIQUETA = "verificacion-arquitectura=1"   # solo se borran contenedores efimeros con esta etiqueta
RED = "reservaviva"            # red unica de compose; Docker le antepone el proyecto (reservaviva-smoke_reservaviva)
RED_ERP = "erpnext_internal"   # red privada de ERPNext (MariaDB, Redis, workers)
CONSULTA_DNS = f"ldap.{DOMINIO}"
# Servicios por TCP publicados en HOST_IP: (nombre, contenedor, puerto dentro del contenedor, variable de test.env con el
# puerto publicado, valor por defecto, tambien en 127.0.0.1). Las 4 apps se publican ademas en 127.0.0.1 con el mismo
# puerto; erpnext-hr es el nginx de ERPNext, el unico contenedor de RRHH que publica (erpnext-backend, gunicorn, no).
SERVICIOS_TCP = [("openvpms", "openvpms-app", "8080/tcp", "OPENVPMS_PORT", 18080, True),
                 ("pretix", "pretix-web", "80/tcp", "PRETIX_PORT", 18082, True),
                 ("inventree", "inventree-app", "8000/tcp", "INVENTREE_PORT", 18083, True),
                 ("erpnext", "erpnext-hr", "8080/tcp", "ERPNEXT_PORT", 18081, True),
                 ("proxy", "proxy-web", "80/tcp", "HTTP_PORT", 80, False),
                 ("ldap", "samba-ad", "389/tcp", "LDAP_PORT", 1389, False),
                 ("ldaps", "samba-ad", "636/tcp", "LDAPS_PORT", 1636, False),
                 ("dns", "dns-interno", "53/tcp", "DNS_PORT", 1053, False)]
SERVICIOS_UDP = [("dns", "dns-interno", "53/udp", "DNS_PORT", 1053), ("ntp", "ntp-interno", "123/udp", "NTP_PORT", 1123)]
# Bases de datos y Redis: se hablan por nombre dentro de la red y NO se publican. contenedor -> puerto en el que escucha.
SIN_PUBLICAR = {"openvpms-db": 3306, "pretix-db": 5432, "pretix-redis": 6379, "inventree-db": 5432, "erpnext-db": 3306,
                "erpnext-redis-cache": 6379, "erpnext-redis-queue": 6379}
# Unicas IP fijas de la red: el DC se provisiona con la suya y la delegacion de ad.reservaviva.lan la necesita.
SUFIJO_DC, SUFIJO_DNS = 10, 11
# Los de ERPNext solo estan en erpnext_internal (no en reservaviva): se les busca desde la pila de red de erpnext-backend.
ERP_PRIVADOS = ("erpnext-db", "erpnext-redis-cache", "erpnext-redis-queue")
ZONA_NOMBRES = ["dns", "ldap", "ntp", "openvpms", "pretix", "inventree", "rrhh"]   # todos -> HOST_IP
# Acceso por nombre a traves del proxy web. Por aplicacion: nombre, pagina HTML que se pide (la de login: la primera que
# ve un usuario) y servicio de SERVICIOS_TCP con el puerto del acceso directo. De esa pagina se saca el primer CSS/JS
# referenciado y tambien se pide (H22: un 200 del HTML no prueba que la web funcione; InvenTree llego a servir el HTML
# sin estaticos).
WEB = {"openvpms": ("/openvpms/login", "openvpms"), "pretix": ("/control/login", "pretix"),
       "inventree": ("/web/", "inventree"), "rrhh": ("/login", "erpnext")}
# Samba AD DC: realm, dominio de la zona AD (delegada por bind9) y grupos por departamento con sus usuarios de prueba.
REALM_AD = "AD.RESERVAVIVA.LAN"
DOMINIO_AD = f"ad.{DOMINIO}"
GRUPOS_AD = {"GG-Medica": ["vet.prueba"], "GG-Operaciones": ["logistica.prueba", "taquilla.prueba"],
             "GG-RRHH": ["rrhh.prueba"]}


# ------------------------------------------------------------------------------------------------
# Mecanica comun: corre tanto en el host (autotest) como DENTRO de los contenedores efimeros (--sonda)
# ------------------------------------------------------------------------------------------------
def tcp_estado(ip, port, timeout=3.0):
    """ABIERTO | RECHAZADO (RST: el destino existe) | SIN_RESPUESTA (timeout: paquete descartado o destino mudo)
    | SIN_RUTA (ICMP inalcanzable / sin ruta) | ERROR. Devuelve (estado, detalle, segundos)."""
    t0 = time.time()
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect((ip, port))
        est, det = "ABIERTO", "conexion establecida"
    except socket.timeout:
        est, det = "SIN_RESPUESTA", f"timeout de {timeout}s: ni SYN-ACK, ni RST, ni ICMP"
    except ConnectionRefusedError as e:
        est, det = "RECHAZADO", f"RST del destino (el host existe y contesta): {e}"
    except OSError as e:
        est = "SIN_RUTA" if e.errno in (errno.EHOSTUNREACH, errno.ENETUNREACH, errno.ENETDOWN, errno.EHOSTDOWN) else "ERROR"
        det = f"errno={e.errno} {e.strerror}"
    finally:
        s.close()
    return est, det, round(time.time() - t0, 2)


def origen_para(ip):
    """IP de origen que el kernel elegiria hacia `ip` (UDP connect no envia nada)."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect((ip, 9))
        o = s.getsockname()[0]
        s.close()
        return o
    except OSError as e:
        return f"?({e.strerror})"


def dns_paquete(nombre, tipo=1, ident=0x1234):
    q = b"".join(bytes([len(p)]) + p.encode() for p in nombre.rstrip(".").split(".")) + b"\0"
    return struct.pack(">HHHHHH", ident, 0x0100, 1, 0, 0, 0) + q + struct.pack(">HH", tipo, 1)


def _salta_nombre(b, i):
    while True:
        n = b[i]
        if n == 0:
            return i + 1
        if n & 0xC0 == 0xC0:
            return i + 2
        i += 1 + n


def _lee_nombre(b, i):
    """Lee un nombre DNS con punteros de compresion (RFC 1035 4.1.4). Devuelve (texto, indice tras el nombre
    EN EL MENSAJE ORIGINAL, sin seguir el salto). Se usa para decodificar el 'target' de un registro SRV."""
    partes, j, salto = [], i, None
    while True:
        n = b[j]
        if n == 0:
            j += 1
            break
        if n & 0xC0 == 0xC0:
            destino = ((n & 0x3F) << 8) | b[j + 1]
            if salto is None:
                salto = j + 2
            j = destino
            continue
        partes.append(b[j + 1:j + 1 + n].decode("ascii", "replace"))
        j += 1 + n
    return ".".join(partes), (salto if salto is not None else j)


def dns_parse(b):
    ident, flags, qd, an, _, _ = struct.unpack(">HHHHHH", b[:12])
    i = 12
    for _ in range(qd):
        i = _salta_nombre(b, i) + 4
    resp, registros_srv = [], []
    for _ in range(an):
        i = _salta_nombre(b, i)
        tipo, _, _, rdl = struct.unpack(">HHIH", b[i:i + 10])
        i += 10
        if tipo == 1 and rdl == 4:
            resp.append(socket.inet_ntoa(b[i:i + 4]))
        elif tipo == 33 and rdl >= 6:   # SRV: prioridad(2) peso(2) puerto(2) + nombre destino
            prioridad, peso, puerto_srv = struct.unpack(">HHH", b[i:i + 6])
            destino, _ = _lee_nombre(b, i + 6)
            registros_srv.append({"prioridad": prioridad, "peso": peso, "puerto": puerto_srv, "destino": destino})
        i += rdl
    return {"rcode": flags & 0xF, "aa": bool(flags & 0x400), "ra": bool(flags & 0x80), "qr": bool(flags & 0x8000),
            "respuestas": resp, "registros_srv": registros_srv, "ident": ident}


def dns_consulta(servidor, nombre, timeout=3.0, puerto=53, tipo=1):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(timeout)
    try:
        s.sendto(dns_paquete(nombre, tipo), (servidor, puerto))
        d, _ = s.recvfrom(2048)
        r = dns_parse(d)
        return r if r["ident"] == 0x1234 else {"error": f"ident distinto {r['ident']:#x}"}
    except socket.timeout:
        return {"error": f"timeout de {timeout}s sin respuesta DNS"}
    except OSError as e:
        return {"error": f"errno={e.errno} {e.strerror}"}
    finally:
        s.close()


def dns_consulta_tcp(servidor, nombre, timeout=5.0, puerto=53, tipo=1):
    """Consulta DNS por TCP (RFC 1035 4.2.2: prefijo de 2 bytes con la longitud). Mismo resultado que dns_consulta."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect((servidor, puerto))
        q = dns_paquete(nombre, tipo)
        s.sendall(struct.pack(">H", len(q)) + q)
        b = b""
        while len(b) < 2 or len(b) < 2 + struct.unpack(">H", b[:2])[0]:
            trozo = s.recv(4096)
            if not trozo:
                return {"error": f"conexion cerrada tras {len(b)} bytes"}
            b += trozo
        r = dns_parse(b[2:])
        return r if r["ident"] == 0x1234 else {"error": f"ident distinto {r['ident']:#x}"}
    except socket.timeout:
        return {"error": f"timeout de {timeout}s sin respuesta DNS (TCP)"}
    except OSError as e:
        return {"error": f"errno={e.errno} {e.strerror}"}
    finally:
        s.close()


def sntp_parse(d, t1, t4):
    b0, stratum = d[0], d[1]
    ref = d[12:16]
    refid = ref.rstrip(b"\0").decode("ascii", "replace") if stratum <= 1 else socket.inet_ntoa(ref)
    seg, frac = struct.unpack(">II", d[40:48])
    ts = seg - 2208988800 + frac / 2 ** 32
    return {"li": b0 >> 6, "vn": (b0 >> 3) & 7, "modo": b0 & 7, "stratum": stratum, "refid": refid,
            "offset_s": round(ts - (t1 + t4) / 2, 4)}


def sntp_consulta(servidor, timeout=3.0, puerto=123):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(timeout)
    try:
        t1 = time.time()
        s.sendto(b"\x23" + 47 * b"\0", (servidor, puerto))
        d, _ = s.recvfrom(512)
        return sntp_parse(d, t1, time.time())
    except socket.timeout:
        return {"error": f"timeout de {timeout}s sin respuesta NTP"}
    except OSError as e:
        return {"error": f"errno={e.errno} {e.strerror}"}
    finally:
        s.close()



def tls_estado(ip, port, nombre, ca_pem, timeout=5.0):
    """Handshake TLS contra ip:port verificando la cadena con `ca_pem` y que el certificado cubra `nombre` (un nombre DNS
    o una IP, que se compara con el SAN). Devuelve (estado, detalle): VERIFICADO | TLS_FALLA | SIN_CONEXION."""
    try:
        ctx = ssl.create_default_context(cadata=ca_pem or None)   # sin CA, la del sistema: no verificara
        with socket.create_connection((ip, port), timeout=timeout) as crudo:
            with ctx.wrap_socket(crudo, server_hostname=nombre) as s:
                cert = s.getpeercert()
                san = [f"{k}:{v}" for k, v in cert.get("subjectAltName", ())]
                return "VERIFICADO", f"{s.version()} verifica la CA y cubre '{nombre}'; SAN={san}"
    except ssl.SSLError as e:   # antes que OSError: SSLError la hereda
        return "TLS_FALLA", f"{type(e).__name__}: {e}"
    except OSError as e:
        return "SIN_CONEXION", f"errno={e.errno} {e.strerror or e}"


def medir(spec):
    """Resultados literales de una medicion: TCP, TLS, DNS (udp) y NTP. Corre en el host o dentro de un contenedor."""
    res = {"tcp": [], "tls": [], "dns": [], "ntp": []}
    for et, ip, port in spec.get("tcp", []):
        est, det, seg = tcp_estado(ip, port)
        res["tcp"].append({"et": et, "ip": ip, "port": port, "estado": est, "detalle": det, "seg": seg,
                           "origen": origen_para(ip)})
    for et, ip, port, nombre in spec.get("tls", []):
        est, det = tls_estado(ip, port, nombre, spec.get("ca", ""))
        res["tls"].append({"et": et, "ip": ip, "port": port, "nombre": nombre, "estado": est, "detalle": det})
    for item in spec.get("dns", []):
        et, srv, nombre, *resto = item   # resto opcional: [tipo, puerto] (tipo 1=A por defecto, 33=SRV; puerto 53)
        tipo, puerto = (resto + [1, 53][len(resto):])[:2]
        res["dns"].append({"et": et, "srv": srv, "puerto": puerto, "nombre": nombre,
                           **dns_consulta(srv, nombre, tipo=tipo, puerto=puerto)})
    for et, srv, *resto in spec.get("ntp", []):   # resto opcional: [puerto] (123 por defecto)
        res["ntp"].append({"et": et, "srv": srv, **sntp_consulta(srv, puerto=(resto[0] if resto else 123))})
    return res


def sonda(spec):
    """Se ejecuta dentro del contenedor efimero. Imprime UNA linea JSON con los resultados literales."""
    print(json.dumps(medir(spec)))


# ------------------------------------------------------------------------------------------------
# Orquestador (host / WSL)
# ------------------------------------------------------------------------------------------------
RESULTADOS = []
SALIDA = []


def imprime(*a):
    linea = " ".join(str(x) for x in a)
    SALIDA.append(linea)
    print(linea, flush=True)


def reg(nombre, veredicto, evidencia):
    RESULTADOS.append((nombre, veredicto))
    imprime(f"  [{veredicto}] {nombre}")
    for l in str(evidencia).splitlines():
        imprime(f"        {l}")


def sh(cmd, entrada=None, timeout=300):
    return subprocess.run(cmd, input=entrada, capture_output=True, text=True, timeout=timeout, cwd=AQUI)


def redes_de(contenedor):
    r = sh(["docker", "inspect", contenedor, "--format", "{{json .NetworkSettings.Networks}}"], timeout=30)
    if r.returncode != 0:
        return None
    return {k: v["IPAddress"] for k, v in json.loads(r.stdout).items()}


def imagen_de(contenedor):
    return sh(["docker", "inspect", contenedor, "--format", "{{.Config.Image}}"], timeout=30).stdout.strip()


def vantage(red, spec, imagen, script):
    """Contenedor efimero. `red` = nombre de red, o 'container:X' para compartir la pila de red de una app."""
    cmd = ["docker", "run", "--rm", "-i", "--pull=never", "--label", ETIQUETA, "--network", red,
           "--entrypoint", "python3", imagen, "-", "--sonda", json.dumps(spec)]
    r = sh(cmd, entrada=script, timeout=240)
    try:
        return json.loads(r.stdout.strip().splitlines()[-1])
    except Exception:
        return {"error": ((r.stderr or "") + (r.stdout or "")).strip()[-400:] or f"rc={r.returncode} sin salida"}


def linea_tcp(t):
    return f"{t['et']} {t['ip']}:{t['port']} desde {t['origen']} -> {t['estado']} ({t['detalle']}; {t['seg']}s)"


def cuerpo_error(res):
    return res.get("error", "") if isinstance(res, dict) else ""


def resp(d):
    """Una respuesta DNS/NTP sin las claves de etiquetado, para mostrarla como evidencia."""
    return {k: v for k, v in d.items() if k not in ("et", "srv", "nombre", "puerto")}


def zona(fichero=ZONA):
    if not fichero.exists():
        return None
    return {m.group(1): m.group(2) for l in fichero.read_text(encoding="utf8").splitlines()
            if (m := re.match(r"^(\S+)\s+IN\s+A\s+(\S+)", l))}


def estado_docker():
    r = sh(["systemctl", "show", "docker", "-p", "ExecMainStartTimestamp"], timeout=30)
    return (r.stdout or r.stderr).strip() or f"rc={r.returncode}"


def config(clave, defecto=""):
    """Valor de una variable: el entorno (el lanzador exporta HOST_IP y `--ip` lo sobrescribe) o, si falta, sistema/test.env."""
    return os.environ.get(clave) or valor_env(clave, defecto)


def parse_bindings(texto):
    """PortBindings de `docker inspect` -> {'80/tcp': [(HostIp, HostPort), ...]}; {} si el contenedor no publica nada."""
    try:
        crudo = json.loads(texto) or {}
        return {p: [(b.get("HostIp") or "0.0.0.0", int(b["HostPort"])) for b in (v or [])] for p, v in crudo.items()}
    except (ValueError, KeyError, TypeError, AttributeError):
        return {}


def bindings(contenedor):
    r = sh(["docker", "inspect", contenedor, "--format", "{{json .HostConfig.PortBindings}}"], timeout=30)
    return parse_bindings(r.stdout)


def publicado(contenedor, puerto):
    """(ip, puerto) en que Docker publica `puerto` (p. ej. '80/tcp') del contenedor, o None. 0.0.0.0 -> 127.0.0.1."""
    b = bindings(contenedor).get(puerto)
    if not b:
        return None
    ip, p = b[0]
    return ("127.0.0.1" if ip in ("0.0.0.0", "") else ip), p


def puertos():
    """Puerto publicado de cada servicio (clave = nombre de SERVICIOS_TCP, mas 'ntp')."""
    p = {n: int(config(var, str(defecto))) for n, _, _, var, defecto, _ in SERVICIOS_TCP}
    p["ntp"] = int(config("NTP_PORT", "1123"))
    return p


def bloque_prereq():
    imprime("\n== Prerrequisitos")
    host = config("HOST_IP")
    if not host:
        reg("HOST_IP definida", "FAIL", "ni el entorno ni sistema/test.env la definen (levantar-sistema la exporta; `--ip X` la fija)")
        return None
    nombres = (["samba-ad", "dns-interno", "ntp-interno", "proxy-web", "erpnext-backend"]
               + [c for _, c, _, _, _, _ in SERVICIOS_TCP] + list(SIN_PUBLICAR))
    redes, ok = {}, True
    for c in dict.fromkeys(nombres):
        r = redes_de(c)
        if r is None:
            reg(f"contenedor {c} existe", "FAIL", "docker inspect fallo: el arnes no esta levantado o el nombre es otro")
            ok = False
        else:
            redes[c] = r
    if not ok:
        return None
    red = next((k for k in redes["samba-ad"] if k.endswith(RED)), None)
    if red is None:
        reg(f"samba-ad esta en la red {RED}", "FAIL", f"redes de samba-ad: {list(redes['samba-ad'])}")
        return None
    pref = red[:-len(RED)]
    comunes = {c: r for c, r in redes.items() if c not in ERP_PRIVADOS}
    fuera = [c for c, r in comunes.items() if not r.get(red)]
    reg(f"los {len(comunes)} contenedores comprobados estan en la red unica {red} con IP", "PASS" if not fuera else "FAIL",
        "\n".join(f"{c}: {r.get(red) or '(sin IP en esa red)'}" for c, r in comunes.items()))
    otras = sorted({k for r in redes.values() for k in r} - {red, pref + RED_ERP})
    reg(f"no hay mas redes que {RED} y {RED_ERP}", "PASS" if not otras else "FAIL",
        f"redes encontradas en esos contenedores: {sorted({k for r in redes.values() for k in r})}")
    erp = [c for c in ("erpnext-backend", "erpnext-hr") + ERP_PRIVADOS if not redes[c].get(pref + RED_ERP)]
    reg(f"erpnext-backend y erpnext-hr estan en {RED_ERP} ademas de {RED}; la BD y los Redis de ERPNext, solo en {RED_ERP}",
        "PASS" if not erp and not any(redes[c].get(red) for c in ERP_PRIVADOS) else "FAIL",
        f"fuera de {RED_ERP}: {erp or 'ninguno'}; BD/Redis de ERPNext tambien en {RED}: {[c for c in ERP_PRIVADOS if redes[c].get(red)] or 'ninguno'}")
    base = config("NET_INTERNA", "10.10.99")
    fijas = {"samba-ad": f"{base}.{SUFIJO_DC}", "dns-interno": f"{base}.{SUFIJO_DNS}"}
    reg("IP fijas: samba-ad y dns-interno (el resto, dinamica)", "PASS" if all(redes[c][red] == ip for c, ip in fijas.items()) else "FAIL",
        "\n".join(f"{c}: esperada {ip}, real {redes[c][red]}" for c, ip in fijas.items()))
    pub = publicado("proxy-web", "80/tcp")
    reg(f"HOST_IP={host} coincide con la IP en que Docker publica proxy-web", "PASS" if pub and pub[0] == host else "FAIL",
        f"HOST_IP (entorno o test.env)={host}; proxy-web 80/tcp publicado en {pub}")
    return {"host": host, "p": puertos(), "red": red, "pref": pref, "ip_dc": redes["samba-ad"][red],
            "ip_dns": redes["dns-interno"][red], "img_py": imagen_de("pretix-web"), "img_ntp": imagen_de("ntp-interno")}


def bloque_medicion(ctx, script):
    """Todas las sondas, juntas: el anfitrion, un contenedor efimero en la red y la pila de red de las apps con LDAPS."""
    host, p = ctx["host"], ctx["p"]
    ca = CA_CRT.read_text(encoding="utf8") if CA_CRT.exists() else ""
    tcp = [(n, host, p[n]) for n, *_ in SERVICIOS_TCP]
    tcp += [(f"cerrado {c}", host, pto) for c, pto in SIN_PUBLICAR.items()]
    spec = {"tcp": tcp, "tls": [("ldaps nombre", host, p["ldaps"], CONSULTA_DNS), ("ldaps IP", host, p["ldaps"], host)],
            "ca": ca, "dns": [("dns", host, CONSULTA_DNS, 1, p["dns"])], "ntp": [("ntp", host, p["ntp"])]}
    m = {"ca": bool(ca), "host": medir(spec), "app": {}}
    # El contenedor efimero ademas busca cada BD/Redis por su NOMBRE: es el control del destino de los negativos.
    interno = [(f"interno {c}", c, pto) for c, pto in SIN_PUBLICAR.items() if c not in ERP_PRIVADOS]
    m["red"] = vantage(ctx["red"], {**spec, "tcp": tcp + interno}, ctx["img_py"], script)
    m["erp"] = vantage("container:erpnext-backend", {"tcp": [(f"interno {c}", c, SIN_PUBLICAR[c]) for c in ERP_PRIVADOS]},
                       ctx["img_py"], script)
    for app in ("inventree-app", "erpnext-backend"):
        m["app"][app] = vantage(f"container:{app}", {"tcp": [("ldaps", host, p["ldaps"])],
                                                     "tls": [("ldaps", host, p["ldaps"], CONSULTA_DNS)], "ca": ca},
                                ctx["img_py"], script)
    return m


def fila(res, lista, et):
    return next((x for x in res.get(lista, []) if x["et"] == et), None)


def bloque_puertos(ctx, m):
    imprime("\n== 1. Puertos: una IP, un puerto por servicio. Ya no hay segmentacion entre departamentos; se comprueba que "
            "cada servicio esta donde debe y que BD y Redis no se publican")
    host, p = ctx["host"], ctx["p"]
    imprime(f"  -- publicacion (docker inspect): HOST_IP={host}; las 4 apps ademas en 127.0.0.1")
    for n, cont, interno, var, _, loopback in SERVICIOS_TCP:
        esperado = {(host, p[n])} | ({("127.0.0.1", p[n])} if loopback else set())
        real = set(bindings(cont).get(interno, []))
        reg(f"{cont} publica {interno} en {', '.join(f'{i}:{q}' for i, q in sorted(esperado))} ({var})",
            "PASS" if real == esperado else "FAIL", f"publicado: {sorted(real) or '(nada)'}")
    for n, cont, interno, var, _ in SERVICIOS_UDP:
        esperado = {(host, p[n] if n == "ntp" else p["dns"])}
        real = set(bindings(cont).get(interno, []))
        reg(f"{cont} publica {interno} en {host}:{next(iter(esperado))[1]} ({var})", "PASS" if real == esperado else "FAIL",
            f"publicado: {sorted(real) or '(nada)'}")

    def abierto(res, titulo, origen):
        if "error" in res:
            reg(f"{titulo}: contenedor de sondeo", "FAIL", cuerpo_error(res))
            return
        for n, cont, *_ in SERVICIOS_TCP:
            t = fila(res, "tcp", n)
            reg(f"{origen} -> {host}:{p[n]} ({n}, {cont}) ABIERTO", "PASS" if t["estado"] == "ABIERTO" else "FAIL", linea_tcp(t))
        d = fila(res, "dns", "dns")
        reg(f"{origen} -> {host}:{p['dns']}/udp (dns): bind9 responde por UDP", "PASS" if "error" not in d and d["rcode"] == 0 else "FAIL",
            f"respuesta={resp(d)}")
        x = fila(res, "ntp", "ntp")
        reg(f"{origen} -> {host}:{p['ntp']}/udp (ntp): ntp-interno responde por UDP",
            "PASS" if "error" not in x and x["modo"] == 4 else "FAIL", f"respuesta={resp(x)}")

    imprime("  -- a) desde el anfitrion (como un equipo de la LAN que llega a HOST_IP)")
    abierto(m["host"], "anfitrion", "anfitrion")
    imprime("  -- b) desde un contenedor efimero de la red (el camino real proxy -> apps)")
    abierto(m["red"], "contenedor en la red", "contenedor")
    imprime(f"  -- c) desde la pila de red de las apps que usan LDAPS: {host}:{p['ldaps']} con TLS verificado (CA del proyecto, "
            f"nombre {CONSULTA_DNS})")
    if not m["ca"]:
        reg("CA del proyecto disponible", "FAIL", f"falta {CA_CRT}: levantar-sistema.sh preparar la genera")
    for app, r in m["app"].items():
        if "error" in r:
            reg(f"{app} (pila de red): contenedor de sondeo", "FAIL", cuerpo_error(r))
            continue
        t, s = fila(r, "tcp", "ldaps"), fila(r, "tls", "ldaps")
        reg(f"{app} -> {host}:{p['ldaps']} (ldaps) ABIERTO", "PASS" if t["estado"] == "ABIERTO" else "FAIL", linea_tcp(t))
        reg(f"{app} -> ldaps {host}:{p['ldaps']}: handshake TLS verificando la CA con el nombre {CONSULTA_DNS}",
            "PASS" if s["estado"] == "VERIFICADO" else "FAIL", f"{s['estado']}: {s['detalle']}")
    s = fila(m["host"], "tls", "ldaps IP")
    reg(f"el certificado LDAPS cubre la IP {host} (SAN IP) y verifica con la CA", "PASS" if s["estado"] == "VERIFICADO" else "FAIL",
        f"{s['estado']}: {s['detalle']}")
    imprime("  -- d) negativos: BD y Redis NO se publican. Controles: HOST_IP alcanzable (proxy abierto) y el servicio "
            "escucha dentro de la red, por su nombre")
    ctl_origen = fila(m["host"], "tcp", "proxy")["estado"] == "ABIERTO"
    for c, pto in SIN_PUBLICAR.items():
        pb = bindings(c)
        reg(f"{c}: sin PortBindings", "PASS" if not pb else "FAIL", f"PortBindings={pb or '{}'}")
        res = m["erp"] if c in ERP_PRIVADOS else m["red"]
        dentro = fila(res, "tcp", f"interno {c}") if "error" not in res else None
        ctl_destino = bool(dentro) and dentro["estado"] == "ABIERTO"
        t = fila(m["host"], "tcp", f"cerrado {c}")
        if not ctl_origen:
            v, why = "FAIL", "inconcluyente: HOST_IP no es alcanzable desde el anfitrion (el proxy no contesta)"
        elif not ctl_destino:
            v, why = "FAIL", "inconcluyente: el servicio no contesta ni dentro de la red, por su nombre"
        elif t["estado"] in ("SIN_RESPUESTA", "SIN_RUTA", "RECHAZADO"):
            v, why = "PASS", f"{t['estado']}: nada escucha en {host}:{pto}, y {c}:{pto} SI contesta dentro de la red"
        elif t["estado"] == "ABIERTO":
            v, why = "FAIL", f"{host}:{pto} esta ABIERTO: o {c} se publica o otro servicio del anfitrion usa ese puerto"
        else:
            v, why = "FAIL", f"error de la sonda ({t['estado']}), no de la red"
        reg(f"{c}: {host}:{pto} NO accesible desde el anfitrion", v,
            linea_tcp(t) + f"\ncontrol dentro de la red: {linea_tcp(dentro) if dentro else '(sin medir)'}\nveredicto: {why}")


def bloque_dns(ctx, m, zonas):
    host, p = ctx["host"], ctx["p"]
    dnsp = p["dns"]
    imprime(f"\n== 2. DNS: una vista y una zona; bind9 consultado de verdad en {host}:{dnsp} (udp y tcp)")
    if zonas is None:
        reg(f"zona {DOMINIO} generada", "FAIL", f"falta {ZONA}. Generarla con: levantar-sistema.sh preparar.")
        return
    faltan = [h for h in ZONA_NOMBRES if h not in zonas]
    reg(f"la zona tiene los {len(ZONA_NOMBRES)} nombres {', '.join(ZONA_NOMBRES)} y todos apuntan a HOST_IP ({host})",
        "PASS" if not faltan and all(zonas[h] == host for h in ZONA_NOMBRES) else "FAIL",
        f"faltan: {faltan or 'ninguno'}; la zona dice { {h: zonas.get(h) for h in ZONA_NOMBRES} }")
    # Desde un contenedor: los nombres por HOST_IP:DNS_PORT, y la delegacion/recursion directo a dns-interno (el origen de
    # una consulta que entra por el puerto publicado es el gateway de la red, que la ACL deja sin recursion).
    ip_dns = ctx["ip_dns"]
    rc = vantage(ctx["red"], {"dns": [(h, host, f"{h}.{DOMINIO}", 1, dnsp) for h in ZONA_NOMBRES] + [
        ("glue", ip_dns, f"dc1.{DOMINIO_AD}"), ("externo", ip_dns, "example.com")]}, ctx["img_py"], SCRIPT)
    if "error" in rc:
        reg("contenedor de sondeo en la red (DNS)", "FAIL", cuerpo_error(rc))
        return
    por = {d["et"]: d for d in rc["dns"]}
    for h in ZONA_NOMBRES:
        fq = f"{h}.{DOMINIO}"
        vias = {"udp (anfitrion)": dns_consulta(host, fq, puerto=dnsp), "tcp (anfitrion)": dns_consulta_tcp(host, fq, puerto=dnsp),
                "udp (contenedor)": por[h]}
        bien = {k: "error" not in d and d["rcode"] == 0 and d["aa"] and d["respuestas"] == [host] for k, d in vias.items()}
        reg(f"{fq} -> {host}: autoritativo por {', '.join(vias)}", "PASS" if all(bien.values()) else "FAIL",
            "\n".join(f"{k} {host}:{dnsp}: " + ("ok " if bien[k] else "MAL ") + f"respuesta={resp(d)}" for k, d in vias.items()))
    d1, d2 = (dns_consulta(host, f"no-existe-xyz.{DOMINIO}", puerto=dnsp), dns_consulta_tcp(host, f"no-existe-xyz.{DOMINIO}", puerto=dnsp))
    reg("nombre inexistente -> NXDOMAIN autoritativo, por udp y tcp (distingue 'nombre desconocido' de 'sin respuesta')",
        "PASS" if all("error" not in d and d["rcode"] == 3 and d["aa"] for d in (d1, d2)) else "FAIL", f"udp={d1}\ntcp={d2}")
    d = dns_consulta(host, "example.com", puerto=dnsp)
    reg(f"example.com desde el anfitrion ({host}:{dnsp}) -> REFUSED (el anfitrion y la LAN no tienen recursion)",
        "PASS" if "error" not in d and d["rcode"] == 5 else "FAIL", f"respuesta={d}")
    g = por["glue"]
    reg(f"delegacion: dc1.{DOMINIO_AD} -> {ctx['ip_dc']} desde un contenedor ({ip_dns}:53; no autoritativo: bind9 la resuelve "
        "por la delegacion hacia samba-ad)", "PASS" if "error" not in g and g["rcode"] == 0 and not g["aa"] and g["respuestas"] == [ctx["ip_dc"]] else "FAIL",
        f"respuesta={resp(g)}")
    d = por["externo"]
    ok = "error" not in d and d["rcode"] in (2, 5) and not d["respuestas"]
    reg(f"example.com desde un contenedor ({ip_dns}:53): sin resolucion real (SERVFAIL o REFUSED, sin respuestas)",
        "PASS" if ok else "FAIL", f"respuesta={resp(d)}")
    if ok and d["rcode"] == 2:
        reg("aviso: los contenedores SI tienen recursion en bind9 (la delegacion de ad.reservaviva.lan la exige)", "INFO",
            f"respuesta={resp(d)}\nSERVFAIL y no REFUSED: bind9 intenta recursionar. Que no resuelva example.com depende de la zona "
            "'.' vacia de named.conf, no de la red: esta red SI tiene salida a Internet.")
    # Con Docker Engine en WSL, dns-interno va a <IP>:DNS_PORT y el 53 de la LAN lo atiende el reenviador de Windows
    # (sistema/reenviador-dns.ps1; ver docs/operacion.md). Se prueba esa ruta completa por UDP y TCP.
    if dnsp != 53:
        pista = ("\nsin respuesta en el 53: el reenviador de Windows no esta en marcha o no reenvia. "
                 "Arrancarlo: .\\levantar-sistema.ps1 arrancar (Windows); comprobarlo: .\\levantar-sistema.ps1 estado")
        for proto, consulta in (("udp", dns_consulta), ("tcp", dns_consulta_tcp)):
            d = consulta(host, f"pretix.{DOMINIO}", puerto=53)
            ok = "error" not in d and d["rcode"] == 0 and d["aa"] and d["respuestas"] == [host]
            reg(f"reenviador de Windows: pretix.{DOMINIO} por {host}:53/{proto} (-> :{dnsp}) -> {host}",
                "PASS" if ok else "FAIL", f"respuesta={d}" + ("" if ok else pista))


def bloque_ntp(ctx, m):
    host, pn = ctx["host"], ctx["p"]["ntp"]
    imprime("\n== 3. NTP: ntp-interno con reloj local (H11: 'server 127.127.1.1' + 'local stratum 10')")
    r = sh(["docker", "exec", "ntp-interno", "chronyc", "tracking"], timeout=60)
    st = re.search(r"^Stratum\s*:\s*(\d+)", r.stdout, re.M)
    reg("chronyc tracking responde dentro de ntp-interno", "PASS" if r.returncode == 0 and st else "FAIL",
        f"rc={r.returncode}\n{(r.stdout or r.stderr).strip()}")
    s = sh(["docker", "exec", "ntp-interno", "chronyc", "sources"], timeout=60)
    reg("chronyc sources (contexto: se espera 127.127.1.1 sin alcanzar; el reloj local lo aporta 'local stratum')", "INFO",
        f"rc={s.returncode}\n{(s.stdout or s.stderr).strip()}")
    if st:
        reg("el stratum publicado por tracking es el esperado (10)", "PASS" if int(st.group(1)) == 10 else "INFO",
            f"Stratum={st.group(1)} (esperado 10 por 'local stratum 10' de /opt/startup.sh)")
    for origen, res in (("anfitrion", m["host"]), ("contenedor", m["red"])):
        x = fila(res, "ntp", "ntp") if "error" not in res else {"error": cuerpo_error(res)}
        ok = "error" not in x and x["modo"] == 4 and 1 <= x["stratum"] <= 15 and x["li"] != 3 and abs(x["offset_s"]) < 5
        reg(f"un cliente SNTP del {origen} recibe hora valida de {host}:{pn}/udp", "PASS" if ok else "FAIL",
            f"respuesta={resp(x)}\ncriterio: modo 4, 1<=stratum<=15, LI!=3 (3 = 'no sincronizado': un cliente lo rechaza), |offset|<5s")
    r = sh(["docker", "run", "--rm", "--pull=never", "--label", ETIQUETA, "--network", ctx["red"],
            "--entrypoint", "chronyd", ctx["img_ntp"], "-Q", f"server {host} port {pn} iburst"], timeout=120)
    txt = (r.stdout + r.stderr).strip()
    ok = r.returncode == 0 and "System clock wrong by" in txt
    reg(f"un cliente chrony REAL (chronyd -Q, no toca el reloj) acepta a {host}:{pn} como fuente", "PASS" if ok else "FAIL",
        f"rc={r.returncode}\n{txt[-500:]}\nSi falla, distinguir: 'No suitable source' = el cliente rechazo al servidor (HALLAZGO); "
        "otro error (p. ej. capacidades) = fallo de la prueba, no del servidor.")


def valor_env(clave, defecto):
    """Valor de sistema/test.env sin ejecutarlo (gana la ultima linea), como valor_env() de levantar-sistema.sh."""
    v = None
    for l in ENV_FILE.read_text(encoding="utf-8").splitlines():
        if l.startswith(clave + "="):
            v = l.split("=", 1)[1].strip()
    return v or defecto



def http_get(ip, puerto, host, ruta, timeout=20):
    """GET sin seguir redirecciones, con el Host indicado (como un navegador que llega por ese nombre)."""
    c = http.client.HTTPConnection(ip, puerto, timeout=timeout)
    try:
        c.request("GET", ruta, headers={"Host": host, "User-Agent": "verificar-arquitectura/1", "Accept": "*/*"})
        r = c.getresponse()
        cuerpo = r.read(2_000_000)
        return {"status": r.status, "ctype": r.getheader("Content-Type", ""), "location": r.getheader("Location", ""),
                "bytes": len(cuerpo), "cuerpo": cuerpo.decode("utf8", "replace")}
    except Exception as e:
        return {"error": f"{type(e).__name__}: {e}"}
    finally:
        c.close()


def websocket_101(ip, puerto, host, ruta, timeout=10):
    """Primera linea de la respuesta a un handshake WebSocket (se espera 'HTTP/1.1 101 ...')."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect((ip, puerto))
        s.sendall((f"GET {ruta} HTTP/1.1\r\nHost: {host}\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n"
                   "Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n").encode())
        return s.recv(1024).decode("latin1").split("\r\n")[0]
    except OSError as e:
        return f"error: {e}"
    finally:
        s.close()


def estatico_de(html, ruta_html):
    """Primer CSS o JS referenciado en la pagina (ruta absoluta dentro del mismo sitio), o None."""
    for m in re.finditer(r'(?:href|src)="([^"]+\.(?:css|js)(?:\?[^"]*)?)"', html):
        u = m.group(1)
        if u.startswith(("http://", "https://", "//")):
            continue
        return urljoin(ruta_html, u)
    return None


def resumen_http(r):
    if "error" in r:
        return r["error"]
    return f"HTTP {r['status']} {r['ctype'] or '(sin Content-Type)'} {r['bytes']} bytes" + \
        (f" Location={r['location']}" if r["location"] else "")


def comprobar_web(etiqueta, ip, puerto, host, ruta):
    """Pagina HTML 200 + su primer estatico 200 con el Content-Type que corresponde. Devuelve la respuesta del HTML."""
    r = http_get(ip, puerto, host, ruta)
    ok = "error" not in r and r["status"] == 200 and "html" in r["ctype"] and "INVE-E7" not in r["cuerpo"]
    reg(f"{etiqueta}: GET {ruta} -> 200 text/html", "PASS" if ok else "FAIL",
        f"{ip}:{puerto} Host: {host} -> {resumen_http(r)}"
        + ("\nel cuerpo trae INVE-E7 (URL visitada distinta de INVENTREE_SITE_URL, H20)" if "INVE-E7" in r.get("cuerpo", "") else ""))
    if not ok:
        return r
    est = estatico_de(r["cuerpo"], ruta)
    if not est:
        reg(f"{etiqueta}: la pagina referencia un CSS/JS", "FAIL", "no se encontro ningun href/src a .css o .js en el HTML")
        return r
    e = http_get(ip, puerto, host, est)
    tipo = "css" if est.split("?")[0].endswith(".css") else "javascript"
    ok = "error" not in e and e["status"] == 200 and tipo in e["ctype"] and e["bytes"] > 0
    reg(f"{etiqueta}: estatico {est} -> 200 ({tipo})", "PASS" if ok else "FAIL",
        f"{ip}:{puerto} Host: {host} -> {resumen_http(e)}")
    return r



def bloque_nombres(ctx):
    host, p = ctx["host"], ctx["p"]
    imprime(f"\n== 4. Acceso por nombre: proxy web (*.{DOMINIO}) y acceso directo por {host}:puerto y por localhost")
    web = (host, p["proxy"])
    # (a) Proxy: por cada nombre, HTML + estatico, con el Host que manda un navegador que llega por ese nombre. El proxy
    # llega a las apps por HOST_IP:puerto, asi que cada 200 prueba tambien ese camino.
    imprime(f"  -- proxy web {web[0]}:{web[1]} con la cabecera Host de cada nombre")
    suf = "" if web[1] == 80 else f":{web[1]}"
    r = http_get(web[0], web[1], f"openvpms.{DOMINIO}{suf}", "/")
    reg(f"openvpms.{DOMINIO}/ redirige a /openvpms/", "PASS" if r.get("status") == 302 and r.get("location", "").endswith("/openvpms/") else "FAIL",
        resumen_http(r))
    for h, (ruta, _) in WEB.items():
        comprobar_web(f"proxy {h}.{DOMINIO}", web[0], web[1], f"{h}.{DOMINIO}{suf}", ruta)
    w = websocket_101(web[0], web[1], f"rrhh.{DOMINIO}{suf}", "/socket.io/?EIO=4&transport=websocket")
    reg(f"proxy rrhh.{DOMINIO}: WebSocket de socket.io (tiempo real de ERPNext) -> 101", "PASS" if " 101 " in w else "FAIL", w)
    r = http_get(web[0], web[1], f"desconocido.{DOMINIO}{suf}", "/")
    reg("nombre desconocido -> 404 del default_server", "PASS" if r.get("status") == 404 and "Reserva Viva" in r.get("cuerpo", "") else "FAIL",
        resumen_http(r) + "\n" + r.get("cuerpo", "")[:200])
    r = http_get(web[0], web[1], host, "/")
    reg("por IP (sin nombre) -> 404 del default_server", "PASS" if r.get("status") == 404 else "FAIL", resumen_http(r))

    # (b) Acceso directo de administracion: HOST_IP:<puerto> (como desde la LAN) y localhost:<puerto> (en el propio equipo).
    imprime(f"  -- acceso directo http://{host}:<puerto> y http://localhost:<puerto> (administracion, docs y verificar)")
    for h, (ruta, svc) in WEB.items():
        puerto = p[svc]
        if h == "pretix":
            # Pretix responde 400 a todo Host que no sea pretix.reservaviva.lan o localhost: por IP:puerto no se entra.
            r = http_get(host, puerto, f"{host}:{puerto}", ruta)
            reg(f"directo {host}:{puerto} (pretix): limitacion conocida, 400 por IP (se entra por nombre o por localhost)",
                "INFO" if "error" not in r else "FAIL", resumen_http(r))
        else:
            comprobar_web(f"directo {host}:{puerto} ({h})", host, puerto, f"{host}:{puerto}", ruta)
        comprobar_web(f"directo localhost:{puerto} ({h})", "127.0.0.1", puerto, f"localhost:{puerto}", ruta)


def bloque_ad(ctx, script):
    imprime("\n== 5. Active Directory: SRV via bind9 (delegacion), Kerberos, grupos y prueba negativa de membresia")
    dns_ip = ctx["ip_dns"]

    # (a) SRV _ldap._tcp y _kerberos._tcp de la zona AD, consultados a bind9 desde un contenedor de la red (los
    # contenedores tienen recursion): demuestra que la delegacion de ad.reservaviva.lan llega de verdad a samba-ad.
    r = vantage(ctx["red"], {"dns": [
        ("srv_ldap", dns_ip, f"_ldap._tcp.{DOMINIO_AD}", 33),
        ("srv_kerberos", dns_ip, f"_kerberos._tcp.{DOMINIO_AD}", 33)]}, ctx["img_py"], script)
    if "error" in r:
        reg("contenedor de sondeo en la red (SRV de AD)", "FAIL", cuerpo_error(r))
    else:
        por = {d["et"]: d for d in r["dns"]}
        for et, puerto_esp, nombre in (("srv_ldap", 389, f"_ldap._tcp.{DOMINIO_AD}"),
                                        ("srv_kerberos", 88, f"_kerberos._tcp.{DOMINIO_AD}")):
            d = por.get(et, {"error": "sin respuesta en la sonda"})
            srv = d.get("registros_srv") or []
            ok = "error" not in d and d.get("rcode") == 0 and any(s["puerto"] == puerto_esp for s in srv)
            reg(f"bind9 ({dns_ip}) delega SRV {nombre} -> puerto {puerto_esp} (samba-ad)",
                "PASS" if ok else "FAIL", f"respuesta={resp(d)}")

    # (b) Kerberos: kinit real dentro de samba-ad. La clave va SIEMPRE por stdin, nunca en argv (visible en
    # 'docker top'/ps de cualquiera con acceso al demonio).
    clave_vet = valor_env("LDAP_PRUEBA_VET_PASSWORD", "")
    if not clave_vet:
        reg(f"kinit vet.prueba@{REALM_AD} (clave por stdin)", "FAIL", "falta LDAP_PRUEBA_VET_PASSWORD en sistema/test.env")
    else:
        rk = sh(["docker", "exec", "-i", "samba-ad", "kinit", f"vet.prueba@{REALM_AD}"], entrada=clave_vet + "\n", timeout=30)
        ok_kinit = rk.returncode == 0
        reg(f"kinit vet.prueba@{REALM_AD} dentro de samba-ad", "PASS" if ok_kinit else "FAIL",
            f"rc={rk.returncode}\n{(rk.stdout + rk.stderr).strip()[-300:]}")
        if ok_kinit:
            rl = sh(["docker", "exec", "samba-ad", "klist"], timeout=30)
            ok_klist = rl.returncode == 0 and "vet.prueba" in rl.stdout and REALM_AD in rl.stdout
            reg("klist: el ticket TGT obtenido es de vet.prueba en el realm esperado", "PASS" if ok_klist else "FAIL",
                (rl.stdout + rl.stderr).strip()[-300:])
        else:
            reg("klist (omitido: kinit fallo, no hay TGT que comprobar)", "FAIL", "ver el resultado de kinit arriba")

    # (c) Grupos: samba-tool group listmembers debe devolver exactamente los usuarios de prueba esperados.
    for grupo, miembros in GRUPOS_AD.items():
        rg = sh(["docker", "exec", "samba-ad", "samba-tool", "group", "listmembers", grupo], timeout=30)
        listados = sorted(l.strip() for l in rg.stdout.splitlines() if l.strip())
        ok = rg.returncode == 0 and listados == sorted(miembros)
        reg(f"samba-tool group listmembers {grupo} == {{{', '.join(sorted(miembros))}}}",
            "PASS" if ok else "FAIL", f"rc={rg.returncode} listados={listados}\n{rg.stderr.strip()[-200:]}")

    # (d) Prueba NEGATIVA de grupos: vet.prueba (solo GG-Medica) no debe poder entrar en InvenTree (exige
    # GG-Operaciones) ni en ERPNext (exige GG-RRHH), porque el filtro LDAP de cada app exige 'memberOf' del
    # grupo correspondiente. Ya no hay red que lo impida: es el unico control de acceso entre departamentos. Se
    # reutiliza ldaplogin.py (mismo mecanismo que Caso 1/2, HTTP dentro de las apps); import diferido: solo se
    # ejecuta aqui, en el orquestador, NUNCA dentro de una sonda efimera (--sonda).
    if str(AQUI) not in sys.path:
        sys.path.insert(0, str(AQUI))
    import ldaplogin
    if not clave_vet:
        reg("prueba negativa: vet.prueba no entra en ERPNext ni InvenTree", "FAIL", "falta LDAP_PRUEBA_VET_PASSWORD")
    else:
        s, t = ldaplogin.http("erpnext-backend", ldaplogin.HTTP_ERP, clave_vet, "vet.prueba", ldaplogin.SITE)
        ok = s in (401, 403, 417)
        reg("prueba negativa: vet.prueba (GG-Medica) NO puede entrar en ERPNext (exige GG-RRHH)",
            "PASS" if ok else "FAIL", f"status={s} (esperado 401/403/417) {t[:120]}")
        s, t = ldaplogin.http("inventree-app", ldaplogin.HTTP_INV, clave_vet, "vet.prueba")
        ok = s in (401, 403)
        reg("prueba negativa: vet.prueba (GG-Medica) NO puede entrar en InvenTree (exige GG-Operaciones)",
            "PASS" if ok else "FAIL", f"status={s} (esperado 401/403) {t[:120]}")


def bloque_consolidado(ctx, persistencia):
    imprime("\n== 6. Consolidacion: se INVOCAN los scripts existentes, sin duplicarlos")
    host, p, img = ctx["host"], ctx["p"], ctx["img_py"]

    def en_la_red(entrada, *args):
        return sh(["docker", "run", "--rm", "-i", "--pull=never", "--label", ETIQUETA, "--network", ctx["red"],
                   "--entrypoint", "python3", img, "-", *args], entrada=entrada, timeout=120)

    sonda_ldap = (AQUI / "ldapprobe.py").read_text(encoding="utf8")
    for destino, ip, puerto in (("por HOST_IP", host, p["ldap"]), ("por la IP fija del DC", ctx["ip_dc"], 389)):
        txt = (lambda r: (r.stdout + r.stderr).strip())(en_la_red(sonda_ldap, ip, str(puerto)))
        reg(f"ldapprobe.py: bind LDAP anonimo + busqueda rootDSE a {ip}:{puerto} desde un contenedor ({destino}, samba-ad)",
            "PASS" if "SONDA LDAP (samba-ad): PASS" in txt else "FAIL", txt[-300:])
    urls = [f"http://{host}:{p['openvpms']}/", f"http://{host}:{p['pretix']}/control/login/",
            f"http://{host}:{p['inventree']}/", f"http://{host}:{p['erpnext']}/"]
    r = en_la_red((AQUI / "probe.py").read_text(encoding="utf8"), *urls)
    txt = (r.stdout + r.stderr).strip()
    for u in urls:
        linea = next((l for l in txt.splitlines() if l.startswith(u)), "(sin salida)")
        reg(f"probe.py: {u} responde HTTP desde un contenedor de la red", "PASS" if linea != "(sin salida)" and " ERR " not in linea else "FAIL",
            linea + "\n(cualquier codigo HTTP prueba que el servicio contesta; Pretix da 400 por IP:puerto, ver H3)")
    args = [sys.executable, str(AQUI / "ldaplogin.py")] + (["--persistencia"] if persistencia else [])
    r = sh(args, timeout=3000)
    txt = r.stdout + r.stderr
    ok = r.returncode == 0 and "VEREDICTO GLOBAL: PASS" in txt
    reg("ldaplogin.py" + (" --persistencia (incluye el caso 4)" if persistencia else " (SIN el caso 4)"),
        "PASS" if ok else "FAIL", f"rc={r.returncode}\n" + "\n".join(txt.strip().splitlines()[-40:]))
    if not persistencia:
        reg("caso 4 de ldaplogin.py (--persistencia)", "FAIL", "NO EJECUTADO por --sin-persistencia: sigue sin verificar")


LIMITES = """
LO QUE UN SOLO HOST NO PUEDE DEMOSTRAR (ver verificar_arquitectura.md): el switch fisico del laboratorio ni el acceso desde
OTROS equipos de la LAN; aqui se prueba desde el propio anfitrion y desde contenedores, y 'pasa en un host' NO es 'pasa en
el laboratorio'. Tampoco hay segmentacion que demostrar: todos los contenedores comparten una red y todo lo publicado queda
accesible en HOST_IP (docs/seguridad.md). Lo que SI se comprueba es lo que se conserva: BD y Redis sin publicar, LDAPS con
CA propia y el control de acceso por grupos de AD dentro de cada aplicacion."""


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sin-persistencia", action="store_true", help="omite ldaplogin.py --persistencia (down + up -d)")
    ap.add_argument("--informe", help="guarda tambien la salida completa en este fichero")
    ap.add_argument("--sonda", help=argparse.SUPPRESS)
    ap.add_argument("--autotest", action="store_true", help="prueba la mecanica con sockets locales, sin Docker")
    a = ap.parse_args()
    if a.sonda:
        sonda(json.loads(a.sonda))
        return 0
    if a.autotest:
        return autotest()
    global SCRIPT
    SCRIPT = Path(__file__).read_text(encoding="utf8")
    inicio = estado_docker()
    imprime(f"docker.service ANTES : {inicio}")
    ctx = bloque_prereq()
    if ctx:
        m = bloque_medicion(ctx, SCRIPT)
        bloque_puertos(ctx, m)
        bloque_dns(ctx, m, zona())
        bloque_ntp(ctx, m)
        bloque_nombres(ctx)
        bloque_ad(ctx, SCRIPT)
        bloque_consolidado(ctx, not a.sin_persistencia)
    fin = estado_docker()
    imprime(f"\ndocker.service DESPUES: {fin}")
    if inicio != fin:
        reg("el demonio docker NO se reinicio durante la prueba", "FAIL", "ExecMainStartTimestamp cambio: el resultado NO VALE, repetir")
    imprime("\n== RESUMEN")
    for n, v in RESULTADOS:
        imprime(f"  [{v}] {n}")
    cuenta = {k: sum(1 for _, v in RESULTADOS if v == k) for k in ("PASS", "FAIL", "INFO")}
    imprime(f"\nPASS={cuenta['PASS']} FAIL={cuenta['FAIL']} INFO={cuenta['INFO']}" + LIMITES)
    imprime("VEREDICTO GLOBAL:", "PASS" if cuenta["FAIL"] == 0 and ctx else "FAIL")
    if a.informe:
        Path(a.informe).write_text("\n".join(SALIDA) + "\n", encoding="utf8")
    return 0 if cuenta["FAIL"] == 0 and ctx else 1


# ------------------------------------------------------------------------------------------------
# Autotest: SOLO mecanica, contra sockets locales. No toca Docker ni el proyecto.
# ------------------------------------------------------------------------------------------------
def _respuesta_dns(consulta, rcode, ips, aa=True):
    ident = struct.unpack(">H", consulta[:2])[0]
    q = consulta[12:]
    flags = 0x8000 | (0x0400 if aa else 0) | rcode
    r = struct.pack(">HHHHHH", ident, flags, 1, len(ips), 0, 0) + q
    for ip in ips:   # puntero de compresion 0xC00C al nombre de la pregunta
        r += b"\xc0\x0c" + struct.pack(">HHIH", 1, 1, 300, 4) + socket.inet_aton(ip)
    return r


def _respuesta_srv(consulta, registros):
    """registros: lista de (prioridad, peso, puerto, destino). El destino se codifica sin compresion (mas
    simple de generar en la prueba); _lee_nombre debe leerlo igual que uno comprimido."""
    ident = struct.unpack(">H", consulta[:2])[0]
    q = consulta[12:]
    flags = 0x8000 | 0x0400
    r = struct.pack(">HHHHHH", ident, flags, 1, len(registros), 0, 0) + q
    for prio, peso, puerto, destino in registros:
        nombre = b"".join(bytes([len(p)]) + p.encode() for p in destino.rstrip(".").split(".")) + b"\0"
        cuerpo = struct.pack(">HHH", prio, peso, puerto) + nombre
        r += b"\xc0\x0c" + struct.pack(">HHIH", 33, 1, 300, len(cuerpo)) + cuerpo
    return r


def autotest():
    fallos = []

    def chk(nombre, cond, det=""):
        imprime(f"  [{'OK' if cond else 'MAL'}] {nombre} {det}")
        if not cond:
            fallos.append(nombre)

    imprime("== autotest de la mecanica (sin Docker, solo loopback)")
    srv = socket.socket(); srv.bind(("127.0.0.1", 0)); srv.listen(1); p = srv.getsockname()[1]
    chk("tcp: puerto con servicio -> ABIERTO", tcp_estado("127.0.0.1", p, 1)[0] == "ABIERTO")
    srv.close()
    chk("tcp: puerto cerrado -> RECHAZADO (distinto de sin respuesta)", tcp_estado("127.0.0.1", p, 1)[0] == "RECHAZADO")
    est = tcp_estado("192.0.2.1", 9, 1)
    chk("tcp: TEST-NET-1 sin destino -> SIN_RESPUESTA o SIN_RUTA, nunca ABIERTO/RECHAZADO",
        est[0] in ("SIN_RESPUESTA", "SIN_RUTA"), f"(obtenido {est[:2]})")

    modo = {"v": (0, ["192.0.2.10"], True)}
    u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); u.bind(("127.0.0.1", 0)); up = u.getsockname()[1]

    def servidor():
        while True:
            try:
                d, dire = u.recvfrom(2048)
            except OSError:
                return
            if d[:1] == b"\x23":   # SNTP
                r = bytearray(48); r[0] = 0x24; r[1] = 10; r[12:16] = socket.inet_aton("127.127.1.1")
                t = time.time() + 2208988800
                r[40:48] = struct.pack(">II", int(t), int((t % 1) * 2 ** 32))
                u.sendto(bytes(r), dire)
            elif modo["v"] is not None:
                u.sendto(_respuesta_dns(d, *modo["v"]), dire)
    threading.Thread(target=servidor, daemon=True).start()
    r = dns_consulta("127.0.0.1", f"ldap.{DOMINIO}", 2, up)
    chk("dns: respuesta autoritativa con puntero de compresion", r.get("rcode") == 0 and r["aa"] and r["respuestas"] == ["192.0.2.10"], f"{r}")
    modo["v"] = (3, [], True)
    r = dns_consulta("127.0.0.1", f"x.{DOMINIO}", 2, up)
    chk("dns: NXDOMAIN se lee como rcode 3 (no como error)", r.get("rcode") == 3 and r["aa"] and not r["respuestas"], f"{r}")
    modo["v"] = (5, [], False)
    r = dns_consulta("127.0.0.1", "example.com", 2, up)
    chk("dns: REFUSED se lee como rcode 5", r.get("rcode") == 5 and not r["aa"], f"{r}")
    modo["v"] = None
    r = dns_consulta("127.0.0.1", f"x.{DOMINIO}", 0.5, up)
    chk("dns: sin respuesta -> error 'timeout' (distinto de NXDOMAIN)", "timeout" in r.get("error", ""), f"{r}")
    r = sntp_consulta("127.0.0.1", 2, up)
    chk("sntp: paquete de stratum 10, LI 0, modo 4 se interpreta bien", r.get("stratum") == 10 and r["li"] == 0 and r["modo"] == 4
        and r["refid"] == "127.127.1.1" and abs(r["offset_s"]) < 1, f"{r}")
    # medir/sonda: el puerto de DNS y NTP viaja en la especificacion (antes la sonda consultaba siempre 53 y 123).
    modo["v"] = (0, ["192.0.2.9"], True)
    r = medir({"dns": [("d", "127.0.0.1", f"ldap.{DOMINIO}", 1, up)], "ntp": [("n", "127.0.0.1", up)]})
    chk("medir: DNS y NTP salen por el puerto indicado en la especificacion",
        r["dns"][0].get("respuestas") == ["192.0.2.9"] and r["ntp"][0].get("stratum") == 10, f"{r}")
    r = medir({"dns": [("d", "127.0.0.1", f"ldap.{DOMINIO}")]})
    chk("medir: sin puerto se usa el 53 (aqui cerrado: no llega al servidor de prueba)", "respuestas" not in r["dns"][0], f"{r}")
    u.close()
    # DNS por TCP: servidor de un solo uso que contesta con prefijo de longitud.
    t = socket.socket(); t.bind(("127.0.0.1", 0)); t.listen(1); tp = t.getsockname()[1]

    def servidor_tcp():
        c, _ = t.accept()
        q = c.recv(2048)[2:]
        resp = _respuesta_dns(q, 0, ["192.0.2.7"])
        c.sendall(struct.pack(">H", len(resp)) + resp)
        c.close()
    threading.Thread(target=servidor_tcp, daemon=True).start()
    r = dns_consulta_tcp("127.0.0.1", f"pretix.{DOMINIO}", 2, tp)
    chk("dns tcp: respuesta con prefijo de longitud se lee igual que por UDP", r.get("rcode") == 0 and r["respuestas"] == ["192.0.2.7"], f"{r}")
    t.close()
    # SRV (tipo 33): usado por el bloque 5 (AD) para _ldap._tcp/_kerberos._tcp. Un solo registro, nombre destino
    # sin compresion (el propio parser sabe leer nombres comprimidos o no: ver _lee_nombre).
    us = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); us.bind(("127.0.0.1", 0)); usp = us.getsockname()[1]

    def servidor_srv():
        d, dire = us.recvfrom(2048)
        us.sendto(_respuesta_srv(d, [(0, 100, 389, "dc1.ad.reservaviva.lan")]), dire)
    threading.Thread(target=servidor_srv, daemon=True).start()
    r = dns_consulta("127.0.0.1", f"_ldap._tcp.ad.{DOMINIO}", 2, usp, tipo=33)
    chk("dns: registro SRV (tipo 33) decodifica prioridad/peso/puerto/destino",
        r.get("rcode") == 0 and r.get("registros_srv") == [{"prioridad": 0, "peso": 100, "puerto": 389,
                                                              "destino": "dc1.ad.reservaviva.lan"}], f"{r}")
    us.close()
    chk("estatico_de: ruta relativa se resuelve contra la pagina",
        estatico_de('<link href="css/a.css">', "/openvpms/login") == "/openvpms/css/a.css")
    chk("estatico_de: se ignoran recursos de otros sitios",
        estatico_de('<script src="https://x.org/a.js"></script><script src="/static/b.js?v=1"></script>', "/web/") == "/static/b.js?v=1")
    z = zona()
    chk("zona: se lee la zona interna generada (o se avisa de que falta)", z is None or ("ldap" in z), f"{z}")
    chk("zona: la zona generada trae los nombres de servicio (o se avisa de que falta)",
        z is None or all(h in z for h in ZONA_NOMBRES), f"{z}")
    b = '{"80/tcp":[{"HostIp":"192.168.1.26","HostPort":"80"}],"53/udp":[{"HostIp":"","HostPort":"1053"}]}'
    chk("parse_bindings: lee IP y puerto publicados (HostIp vacio = 0.0.0.0)",
        parse_bindings(b) == {"80/tcp": [("192.168.1.26", 80)], "53/udp": [("0.0.0.0", 1053)]}, f"{parse_bindings(b)}")
    chk("parse_bindings: un contenedor sin puertos publicados ({} o null) -> {}", parse_bindings("{}") == {} == parse_bindings("null"))
    # TLS: puerto sin servicio -> SIN_CONEXION; un servidor que no habla TLS -> TLS_FALLA (no se confunde con lo anterior).
    t = socket.socket(); t.bind(("127.0.0.1", 0)); t.listen(1); tp = t.getsockname()[1]

    def servidor_basura():
        c, _ = t.accept()
        c.sendall(b"esto no es TLS\r\n")
        c.close()
    threading.Thread(target=servidor_basura, daemon=True).start()
    chk("tls: un servidor que no habla TLS -> TLS_FALLA", tls_estado("127.0.0.1", tp, "ldap.reservaviva.lan", "", 2)[0] == "TLS_FALLA")
    t.close()
    chk("tls: puerto cerrado -> SIN_CONEXION", tls_estado("127.0.0.1", tp, "ldap.reservaviva.lan", "", 2)[0] == "SIN_CONEXION")
    imprime(f"\nautotest: {'PASS' if not fallos else 'FAIL ' + str(fallos)}   (mecanica solamente; el arnes NO se ejecuto)")
    return 0 if not fallos else 1


SCRIPT = None   # se rellena en main(): dentro del contenedor el script llega por stdin y no hay __file__

if __name__ == "__main__":
    sys.exit(main())
