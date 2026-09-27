#!/usr/bin/env python3
"""Verificacion de que la ARQUITECTURA (no solo los contenedores) se comporta como esta disenada, en un host.

Ejecutado contra el sistema completo el 2026-09-26 (levantar-sistema.sh verificar: 92 PASS, 0 FAIL). `--autotest`
prueba la mecanica (clasificador de conexiones, cliente DNS, cliente SNTP, lector de zona) contra sockets locales,
sin tocar Docker. Ver verificar_arquitectura.md para el alcance y sus limites.

Requisito: el arnes levantado (`docker compose up -d` en esta carpeta) y sano. Ejecutar donde `docker` sea el cliente
nativo (p. ej. dentro de WSL), igual que ldaplogin.py. Sin dependencias fuera de la libreria estandar.

Uso (desde esta carpeta):
    python3 verificar_arquitectura.py                     # todos los bloques, incluido ldaplogin.py --persistencia
    python3 verificar_arquitectura.py --sin-persistencia  # sin el caso 4 (que hace down + up -d y tarda)
    python3 verificar_arquitectura.py --informe out.txt   # ademas guarda la salida completa
    python3 verificar_arquitectura.py --autotest          # solo la mecanica, sin Docker

Bloques: 1 segmentacion (prueba negativa) | 2 DNS (bind9 consultado de verdad) | 3 NTP | 4 consolidacion
(ldapprobe.py, probe.py, ldaplogin.py, sin duplicarlos).
Cada comprobacion da PASS / FAIL / INFO con la salida literal en la que se apoya. Sale con 0 SOLO si no hay ningun FAIL.
INFO no cuenta: son hallazgos que hay que leer, no fallos del guion.

Por que un fallo tiene que ocurrir por la razon correcta: un destino inalcanzable y un nombre que no resuelve dan
resultados parecidos. Aqui los negativos usan SIEMPRE una IP literal (el DNS no interviene) y solo cuentan como PASS si
(a) el cliente prueba, desde su propia VLAN, que su herramienta funciona (control positivo) y (b) el destino contesta
desde SU propia VLAN (control del destino). Un timeout sin esos dos controles no prueba nada y se marca FAIL.
"""
import argparse, errno, json, re, socket, struct, subprocess, sys, threading, time
from pathlib import Path

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parent
ZONA = RAIZ / "docker/pc3-administracion-infra/bind/zones/db.reservaviva.local"
ETIQUETA = "verificacion-arquitectura=1"   # solo se borran contenedores efimeros con esta etiqueta
# depto -> (contenedor de la app dual-homed, puerto TCP donde escucha). Cada app esta ademas en vlan99_infra.
APPS = {10: ("openvpms-app", 8080), 20: ("pretix-web", 80), 30: ("inventree-app", 8000), 40: ("erpnext-backend", 8000)}
APP_DEPTO = {a: d for d, (a, _) in APPS.items()}
RED = {10: "vlan10_medica", 20: "vlan20_taquilla", 30: "vlan30_logistica", 40: "vlan40_rrhh", 99: "vlan99_infra"}
CONSULTA_DNS = "ldap.reservaviva.local"
# nombre de la zona -> (contenedor que da ese servicio, VLAN donde se le busca la IP real). bloque_dns compara la zona
# generada con `docker inspect`. rrhh -> erpnext-hr: es el nginx de ERPNext, el unico contenedor de RRHH que atiende HTTP
# a los usuarios (escucha en 8080 y es el que publica ERPNEXT_PORT en el host); erpnext-backend (gunicorn, 8000) no
# publica nada y solo se le llega a traves de ese nginx. Comprobado con docker inspect el 26/09/2026.
ZONA_ESPERADA = {"dns": ("dns-interno", 99), "ldap": ("openldap", 99), "ntp": ("ntp-interno", 99),
                 "openvpms": ("openvpms-app", 10), "pretix": ("pretix-web", 20), "inventree": ("inventree-app", 30),
                 "rrhh": ("erpnext-hr", 40)}


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


def rutas():
    out = []
    try:
        ip = lambda h: socket.inet_ntoa(struct.pack("<L", int(h, 16)))
        for l in open("/proc/net/route").read().splitlines()[1:]:
            f = l.split()
            out.append(f"{f[0]} dest={ip(f[1])} mask={ip(f[7])} gw={ip(f[2])}")
    except OSError as e:
        out.append(f"no se pudo leer /proc/net/route: {e}")
    return out


def dns_paquete(nombre, ident=0x1234):
    q = b"".join(bytes([len(p)]) + p.encode() for p in nombre.rstrip(".").split(".")) + b"\0"
    return struct.pack(">HHHHHH", ident, 0x0100, 1, 0, 0, 0) + q + struct.pack(">HH", 1, 1)


def _salta_nombre(b, i):
    while True:
        n = b[i]
        if n == 0:
            return i + 1
        if n & 0xC0 == 0xC0:
            return i + 2
        i += 1 + n


def dns_parse(b):
    ident, flags, qd, an, _, _ = struct.unpack(">HHHHHH", b[:12])
    i = 12
    for _ in range(qd):
        i = _salta_nombre(b, i) + 4
    resp = []
    for _ in range(an):
        i = _salta_nombre(b, i)
        tipo, _, _, rdl = struct.unpack(">HHIH", b[i:i + 10])
        i += 10
        if tipo == 1 and rdl == 4:
            resp.append(socket.inet_ntoa(b[i:i + 4]))
        i += rdl
    return {"rcode": flags & 0xF, "aa": bool(flags & 0x400), "ra": bool(flags & 0x80), "qr": bool(flags & 0x8000),
            "respuestas": resp, "ident": ident}


def dns_consulta(servidor, nombre, timeout=3.0, puerto=53):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(timeout)
    try:
        s.sendto(dns_paquete(nombre), (servidor, puerto))
        d, _ = s.recvfrom(2048)
        r = dns_parse(d)
        return r if r["ident"] == 0x1234 else {"error": f"ident distinto {r['ident']:#x}"}
    except socket.timeout:
        return {"error": f"timeout de {timeout}s sin respuesta DNS"}
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


def sonda(spec):
    """Se ejecuta dentro del contenedor efimero. Imprime UNA linea JSON con los resultados literales."""
    res = {"rutas": rutas(), "tcp": [], "dns": [], "ntp": []}
    for et, ip, port in spec.get("tcp", []):
        est, det, seg = tcp_estado(ip, port)
        res["tcp"].append({"et": et, "ip": ip, "port": port, "estado": est, "detalle": det, "seg": seg,
                           "origen": origen_para(ip)})
    for et, srv, nombre in spec.get("dns", []):
        res["dns"].append({"et": et, "srv": srv, "nombre": nombre, **dns_consulta(srv, nombre)})
    for et, srv in spec.get("ntp", []):
        res["ntp"].append({"et": et, "srv": srv, **sntp_consulta(srv)})
    print(json.dumps(res))


def juzga_negativo(estado, control_origen_ok, control_destino_ok):
    """PASS solo si NO hay ruta/respuesta Y los dos controles prueban que la prueba es valida."""
    if not control_origen_ok:
        return "FAIL", "inconcluyente: el control positivo del ORIGEN fallo (la herramienta o la red del cliente no funcionan)"
    if not control_destino_ok:
        return "FAIL", "inconcluyente: el DESTINO no contesto ni desde su propia VLAN; un timeout no prueba segmentacion"
    if estado in ("SIN_RESPUESTA", "SIN_RUTA"):
        return "PASS", f"{estado}: no hay camino hacia el destino, que si contesta desde su VLAN"
    if estado in ("ABIERTO", "RECHAZADO"):
        return "FAIL", f"SEGMENTACION ROTA: el destino contesto ({estado})"
    return "FAIL", f"error de la sonda ({estado}), no de la red"


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
    """Contenedor efimero. `red` = nombre de red, o 'container:X' para compartir la pila de red de una app dual-homed."""
    cmd = ["docker", "run", "--rm", "-i", "--pull=never", "--label", ETIQUETA, "--network", red,
           "--entrypoint", "python3", imagen, "-", "--sonda", json.dumps(spec)]
    r = sh(cmd, entrada=script, timeout=240)
    try:
        return json.loads(r.stdout.strip().splitlines()[-1])
    except Exception:
        return {"error": ((r.stderr or "") + (r.stdout or "")).strip()[-400:] or f"rc={r.returncode} sin salida"}


def linea_tcp(t):
    return f"{t['et']} {t['ip']}:{t['port']} desde {t['origen']} -> {t['estado']} ({t['detalle']}; {t['seg']}s)"


def tcp_de(res, prefijo):
    return [t for t in res.get("tcp", []) if t["et"].startswith(prefijo)]


def cuerpo_error(res):
    return res.get("error", "") if isinstance(res, dict) else ""


def zona():
    if not ZONA.exists():
        return None
    return {m.group(1): m.group(2) for l in ZONA.read_text(encoding="utf8").splitlines()
            if (m := re.match(r"^(\S+)\s+IN\s+A\s+(\S+)", l))}


def ip_real(ctx, contenedor, d):
    """IP del contenedor en la VLAN d ('' si no esta en ella). Reutiliza lo ya inspeccionado en los prerrequisitos."""
    if contenedor in ctx["ips"]:
        return ctx["ips"][contenedor].get(d, "")
    return (redes_de(contenedor) or {}).get(ctx["pref"] + RED[d], "")


def estado_docker():
    r = sh(["systemctl", "show", "docker", "-p", "ExecMainStartTimestamp"], timeout=30)
    return (r.stdout or r.stderr).strip() or f"rc={r.returncode}"


def bloque_prereq():
    imprime("\n== Prerrequisitos")
    ips, ok = {}, True
    for c in ["openldap", "dns-interno", "ntp-interno"] + [a for a, _ in APPS.values()]:
        redes = redes_de(c)
        if redes is None:
            reg(f"contenedor {c} existe", "FAIL", "docker inspect fallo: el arnes no esta levantado o el nombre es otro")
            ok = False
            continue
        ips[c] = redes
    if not ok:
        return None
    pref = next((k[:-len(RED[99])] for k in ips["openldap"] if k.endswith(RED[99])), None)
    if pref is None:
        reg("openldap esta en vlan99_infra", "FAIL", f"redes de openldap: {list(ips['openldap'])}")
        return None
    por_depto = {}
    for nombre, redes in ips.items():
        por_depto[nombre] = {v: redes.get(pref + n, "") for v, n in RED.items()}
    faltan = [f"{a}@vlan{d}" for a, _ in APPS.values() for d in (10, 20, 30, 40, 99)
              if (d == 99 or APPS[d][0] == a) and not por_depto[a][d]]  # d == 99 primero: APPS no tiene clave 99
    for d, (a, _) in APPS.items():
        if not por_depto[a][d] or not por_depto[a][99]:
            faltan.append(f"{a} no esta dual-homed (vlan{d} + vlan99)")
    if faltan:
        reg("las 4 apps estan en su VLAN y en vlan99_infra con IP", "FAIL", "; ".join(sorted(set(faltan))))
        return None
    reg("las 4 apps estan en su VLAN y en vlan99_infra con IP", "PASS",
        "\n".join(f"{a}: vlan{d}={por_depto[a][d]} vlan99={por_depto[a][99]}" for d, (a, _) in APPS.items())
        + f"\nopenldap={por_depto['openldap'][99]} dns-interno={por_depto['dns-interno'][99]} ntp-interno={por_depto['ntp-interno'][99]}")
    return {"ips": por_depto, "pref": pref, "img_py": imagen_de("pretix-web"), "img_ntp": imagen_de("ntp-interno")}


def bloque_medicion(ctx, script):
    """Todos los contenedores efimeros de sondeo, juntos, para poder cruzar controles despues."""
    ips, pref, img = ctx["ips"], ctx["pref"], ctx["img_py"]
    ldap = ips["openldap"][99]
    dns_ip, ntp_ip = ips["dns-interno"][99], ips["ntp-interno"][99]
    m = {"dept": {}, "dual": {}}
    m["infra"] = vantage(pref + RED[99], {
        "tcp": [("openldap:389", ldap, 389), ("openldap:636", ldap, 636)],
        "dns": [("zona", dns_ip, CONSULTA_DNS)], "ntp": [("ntp", ntp_ip)]}, img, script)
    for d, (app, port) in APPS.items():
        tcp = [(f"control {app}@vlan{d}", ips[app][d], port)]
        for e, (app_e, port_e) in APPS.items():
            if e != d:
                tcp += [(f"{app_e}@vlan{e}", ips[app_e][e], port_e), (f"{app_e}@vlan99", ips[app_e][99], port_e)]
        tcp += [("openldap:389", ldap, 389), ("openldap:636", ldap, 636)]
        m["dept"][d] = vantage(pref + RED[d], {"tcp": tcp, "dns": [("dns", dns_ip, CONSULTA_DNS)],
                                               "ntp": [("ntp", ntp_ip)]}, img, script)
        tcp = [("openldap:389", ldap, 389), ("openldap:636", ldap, 636)]
        for e, (app_e, port_e) in APPS.items():
            if e != d:
                tcp += [(f"{app_e}@vlan{e}", ips[app_e][e], port_e), (f"{app_e}@vlan99", ips[app_e][99], port_e)]
        m["dual"][d] = vantage(f"container:{app}", {"tcp": tcp, "dns": [("dns", dns_ip, CONSULTA_DNS)],
                                                    "ntp": [("ntp", ntp_ip)]}, img, script)
    return m


def bloque_segmentacion(ctx, m):
    imprime("\n== 1. Segmentacion (prueba negativa). PASS = 'no hay camino', nunca 'no respondio' sin controles")
    ips = ctx["ips"]
    ctl_ok = {}
    for d, (app, _) in APPS.items():
        r = m["dept"][d]
        if "error" in r:
            reg(f"vlan{d}: contenedor de sondeo", "FAIL", cuerpo_error(r))
            ctl_ok[d] = False
            continue
        c = tcp_de(r, "control")[0]
        ctl_ok[d] = c["estado"] == "ABIERTO"
        reg(f"control positivo vlan{d}: un cliente en vlan{d} alcanza {app}", "PASS" if ctl_ok[d] else "FAIL",
            linea_tcp(c) + "\nrutas del cliente: " + " | ".join(r["rutas"]))
    imprime("  -- cliente SOLO en su VLAN de departamento (no dual-homed)")
    for d in APPS:
        r = m["dept"][d]
        if "error" in r:
            continue
        for t in r["tcp"]:
            if t["et"].startswith("control"):
                continue
            if t["et"].startswith("openldap"):
                infra_ok = any(x["estado"] == "ABIERTO" and x["et"] == t["et"] for x in m["infra"].get("tcp", []))
                v, why = juzga_negativo(t["estado"], ctl_ok[d], infra_ok)
                nombre = f"vlan{d} (solo departamento) -> {t['et']} debe FALLAR (no esta dual-homed)"
            else:
                app_t, e = t["et"].split("@vlan")
                destino_ok = ctl_ok.get(APP_DEPTO[app_t], False)   # la app escucha en 0.0.0.0: si contesta en su VLAN, escucha
                v, why = juzga_negativo(t["estado"], ctl_ok[d], destino_ok)
                nombre = f"vlan{d} -> {t['et']} debe FALLAR"
            reg(nombre, v, linea_tcp(t) + f"\nveredicto: {why}")
    imprime("  -- cliente con la pila de red de la app (dual-homed): SI llega a infraestructura, NO a otros departamentos")
    for d, (app, _) in APPS.items():
        r = m["dual"][d]
        if "error" in r:
            reg(f"{app} (dual-homed): contenedor de sondeo", "FAIL", cuerpo_error(r))
            continue
        for t in tcp_de(r, "openldap"):
            reg(f"{app} -> {t['et']} debe FUNCIONAR (cruce previsto hacia infraestructura)",
                "PASS" if t["estado"] == "ABIERTO" else "FAIL", linea_tcp(t))
        ctl_dual = all(t["estado"] == "ABIERTO" for t in tcp_de(r, "openldap"))
        for t in r["tcp"]:
            if t["et"].startswith("openldap"):
                continue
            app_t, e = t["et"].split("@vlan")
            e = int(e)
            if e == 99:
                reg(f"{app} -> {t['et']} (otra app, por la VLAN de infraestructura)", "INFO",
                    linea_tcp(t) + "\nHALLAZGO a leer: vlan99_infra es un unico dominio L2 compartido por las 4 apps; si sale ABIERTO, "
                    "un bridge NO impide que dos apps de departamentos distintos hablen entre si por infraestructura. "
                    "En el laboratorio real lo limita la matriz de firewall de PC-3, que un host no reproduce.")
            else:
                v, why = juzga_negativo(t["estado"], ctl_dual, ctl_ok.get(e, False))
                reg(f"{app} -> {t['et']} debe FALLAR (departamentos aislados aunque la app sea dual-homed)", v,
                    linea_tcp(t) + f"\nveredicto: {why}")


def bloque_dns(ctx, m, zonas):
    imprime("\n== 2. DNS: se consulta a dns-interno de verdad (los contenedores normales usan extra_hosts / DNS de Docker)")
    dns_ip = ctx["ips"]["dns-interno"][99]
    if zonas is None:
        reg("zona reservaviva.local generada", "FAIL", f"falta {ZONA}. Generarla con: levantar-sistema.sh preparar.")
        return
    nombres = [(f"{h}.reservaviva.local", ip) for h, ip in zonas.items()]
    inf = vantage(ctx["pref"] + RED[99], {"dns": [(h, dns_ip, h) for h, _ in nombres] + [
        ("inexistente", dns_ip, "no-existe-xyz.reservaviva.local"), ("externo", dns_ip, "example.com")]},
        ctx["img_py"], SCRIPT)
    if "error" in inf:
        reg("contenedor de sondeo en vlan99", "FAIL", cuerpo_error(inf))
        return
    por = {d["et"]: d for d in inf["dns"]}
    for h, ip in nombres:
        d = por[h]
        ok = "error" not in d and d["rcode"] == 0 and d["aa"] and d["respuestas"] == [ip]
        reg(f"{h} -> {ip} (autoritativo, igual que la zona)", "PASS" if ok else "FAIL",
            f"servidor={dns_ip} respuesta={ {k: v for k, v in d.items() if k not in ('et', 'srv')} }")
    d = por["inexistente"]
    reg("nombre inexistente -> NXDOMAIN autoritativo (distingue 'nombre desconocido' de 'sin respuesta')",
        "PASS" if "error" not in d and d["rcode"] == 3 and d["aa"] else "FAIL", f"respuesta={d}")
    d = por["externo"]
    reg("example.com -> REFUSED (sin recursion: la zona interna no sale a Internet)",
        "PASS" if "error" not in d and d["rcode"] == 5 else "FAIL", f"respuesta={d}")
    # Cada nombre de la zona debe resolver a la IP real (docker inspect) del contenedor que da ese servicio.
    for h, (cont, d_) in ZONA_ESPERADA.items():
        real = ip_real(ctx, cont, d_) or f"(sin IP en vlan{d_})"
        nombre = f"zona: {h}.reservaviva.local apunta a {cont} (su IP real en vlan{d_})"
        if h not in zonas:
            reg(nombre, "FAIL", f"la zona no tiene el nombre '{h}'; {cont} esta en {real}")
        else:
            reg(nombre, "PASS" if zonas[h] == real else "FAIL", f"la zona dice {zonas[h]}, el contenedor real esta en {real}")
    imprime("  -- los clientes solo de departamento NO deben alcanzar el DNS interno (UDP; control = la consulta de arriba)")
    ctl = all(por[h]["rcode"] == 0 for h, _ in nombres if "error" not in por[h]) and "error" not in por[nombres[0][0]]
    for d_, (app, _) in APPS.items():
        r = m["dept"][d_]
        x = (r.get("dns") or [{}])[0]
        if "error" in r:
            continue
        v = ("PASS" if ("error" in x and "timeout" in x["error"]) else "FAIL") if ctl else "FAIL"
        reg(f"vlan{d_} (solo departamento) -> dns-interno {dns_ip}:53/udp debe quedar SIN RESPUESTA", v,
            f"respuesta={ {k: v_ for k, v_ in x.items() if k not in ('et',)} }"
            + ("" if ctl else "\ninconcluyente: el control desde vlan99 no obtuvo respuesta"))
    for d_, (app, _) in APPS.items():
        r = m["dual"][d_]
        x = (r.get("dns") or [{}])[0]
        reg(f"{app} (dual-homed) -> dns-interno debe RESPONDER", "PASS" if "error" not in x and x.get("rcode") == 0 else "FAIL",
            f"respuesta={ {k: v for k, v in x.items() if k not in ('et',)} }")


def bloque_ntp(ctx, m):
    imprime("\n== 3. NTP: ntp-interno con reloj local (H11: 'server 127.127.1.1' + 'local stratum 10')")
    ntp_ip = ctx["ips"]["ntp-interno"][99]
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
    x = (m["infra"].get("ntp") or [{}])[0]
    ok = "error" not in x and x["modo"] == 4 and 1 <= x["stratum"] <= 15 and x["li"] != 3 and abs(x["offset_s"]) < 5
    reg(f"un cliente SNTP en vlan99 recibe hora valida de {ntp_ip}:123", "PASS" if ok else "FAIL",
        f"respuesta={ {k: v for k, v in x.items() if k not in ('et',)} }\n"
        "criterio: modo 4, 1<=stratum<=15, LI!=3 (3 = 'no sincronizado': un cliente lo rechaza), |offset|<5s")
    r = sh(["docker", "run", "--rm", "--pull=never", "--label", ETIQUETA, "--network", ctx["pref"] + RED[99],
            "--entrypoint", "chronyd", ctx["img_ntp"], "-Q", f"server {ntp_ip} iburst"], timeout=120)
    txt = (r.stdout + r.stderr).strip()
    ok = r.returncode == 0 and "System clock wrong by" in txt
    reg("un cliente chrony REAL (chronyd -Q, no toca el reloj) acepta a ntp-interno como fuente", "PASS" if ok else "FAIL",
        f"rc={r.returncode}\n{txt[-500:]}\nSi falla, distinguir: 'No suitable source' = el cliente rechazo al servidor (HALLAZGO); "
        "otro error (p. ej. capacidades) = fallo de la prueba, no del servidor.")
    for d_, (app, _) in APPS.items():
        y = (m["dept"][d_].get("ntp") or [{}])[0]
        v = "PASS" if "error" in y and "timeout" in y["error"] and "error" not in x else "FAIL"
        reg(f"vlan{d_} (solo departamento) -> ntp-interno {ntp_ip}:123/udp debe quedar SIN RESPUESTA", v,
            f"respuesta={ {k: v_ for k, v_ in y.items() if k not in ('et',)} }")
        z = (m["dual"][d_].get("ntp") or [{}])[0]
        reg(f"{app} (dual-homed) -> ntp-interno debe RESPONDER", "PASS" if "error" not in z else "FAIL",
            f"respuesta={ {k: v for k, v in z.items() if k not in ('et',)} }")


def bloque_consolidado(ctx, persistencia):
    imprime("\n== 4. Consolidacion: se INVOCAN los scripts existentes, sin duplicarlos")
    img = ctx["img_py"]
    r = sh(["docker", "run", "--rm", "-i", "--pull=never", "--label", ETIQUETA, "--network", ctx["pref"] + RED[99],
            "--entrypoint", "python3", img, "-"], entrada=(AQUI / "ldapprobe.py").read_text(encoding="utf8"), timeout=120)
    txt = (r.stdout + r.stderr).strip()
    reg("ldapprobe.py: bind LDAP anonimo crudo a 10.10.99.10:389 desde vlan99",
        "PASS" if "respuesta LDAP BindResponse" in txt else "FAIL", txt[-300:])
    urls = {10: "http://{ip}:8080/", 20: "http://{ip}:80/control/login/", 30: "http://{ip}:8000/", 40: "http://{ip}:8000/"}
    for d, (app, _) in APPS.items():
        ip = ctx["ips"][app][d]
        r = sh(["docker", "run", "--rm", "-i", "--pull=never", "--label", ETIQUETA, "--network", ctx["pref"] + RED[d],
                "--entrypoint", "python3", img, "-", urls[d].format(ip=ip)],
               entrada=(AQUI / "probe.py").read_text(encoding="utf8"), timeout=120)
        txt = (r.stdout + r.stderr).strip()
        reg(f"probe.py: {app} responde HTTP desde su propia vlan{d}", "PASS" if r.stdout.strip() and " ERR " not in txt else "FAIL",
            txt[-300:] + "\n(cualquier codigo HTTP prueba que el servicio contesta; p. ej. Pretix da 400 sin el Host correcto, ver H3)")
    args = [sys.executable, str(AQUI / "ldaplogin.py")] + (["--persistencia"] if persistencia else [])
    r = sh(args, timeout=3000)
    txt = r.stdout + r.stderr
    ok = r.returncode == 0 and "VEREDICTO GLOBAL: PASS" in txt
    reg("ldaplogin.py" + (" --persistencia (incluye el caso 4)" if persistencia else " (SIN el caso 4)"),
        "PASS" if ok else "FAIL", f"rc={r.returncode}\n" + "\n".join(txt.strip().splitlines()[-40:]))
    if not persistencia:
        reg("caso 4 de ldaplogin.py (--persistencia)", "FAIL", "NO EJECUTADO por --sin-persistencia: sigue sin verificar")


LIMITES = """
LO QUE UN SOLO HOST NO PUEDE DEMOSTRAR (ver verificar_arquitectura.md): etiquetado 802.1Q y puertos troncales,
el switch fisico, y la matriz de firewall de PC-3 sobre interfaces reales. Aqui cada VLAN es un bridge de Docker con
la misma subred: 'pasa en un host' NO es 'pasa en el laboratorio'."""


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
        bloque_segmentacion(ctx, m)
        bloque_dns(ctx, m, zona())
        bloque_ntp(ctx, m)
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
    for est_, co, cd, esp in [("SIN_RESPUESTA", True, True, "PASS"), ("SIN_RUTA", True, True, "PASS"),
                              ("ABIERTO", True, True, "FAIL"), ("RECHAZADO", True, True, "FAIL"),
                              ("SIN_RESPUESTA", False, True, "FAIL"), ("SIN_RESPUESTA", True, False, "FAIL"),
                              ("ERROR", True, True, "FAIL")]:
        chk(f"juzga_negativo({est_}, origen_ok={co}, destino_ok={cd}) -> {esp}", juzga_negativo(est_, co, cd)[0] == esp)

    modo = {"v": (0, ["10.10.99.10"], True)}
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
    r = dns_consulta("127.0.0.1", "ldap.reservaviva.local", 2, up)
    chk("dns: respuesta autoritativa con puntero de compresion", r.get("rcode") == 0 and r["aa"] and r["respuestas"] == ["10.10.99.10"], f"{r}")
    modo["v"] = (3, [], True)
    r = dns_consulta("127.0.0.1", "x.reservaviva.local", 2, up)
    chk("dns: NXDOMAIN se lee como rcode 3 (no como error)", r.get("rcode") == 3 and r["aa"] and not r["respuestas"], f"{r}")
    modo["v"] = (5, [], False)
    r = dns_consulta("127.0.0.1", "example.com", 2, up)
    chk("dns: REFUSED se lee como rcode 5", r.get("rcode") == 5 and not r["aa"], f"{r}")
    modo["v"] = None
    r = dns_consulta("127.0.0.1", "x.reservaviva.local", 0.5, up)
    chk("dns: sin respuesta -> error 'timeout' (distinto de NXDOMAIN)", "timeout" in r.get("error", ""), f"{r}")
    r = sntp_consulta("127.0.0.1", 2, up)
    chk("sntp: paquete de stratum 10, LI 0, modo 4 se interpreta bien", r.get("stratum") == 10 and r["li"] == 0 and r["modo"] == 4
        and r["refid"] == "127.127.1.1" and abs(r["offset_s"]) < 1, f"{r}")
    u.close()
    z = zona()
    chk("zona: se lee la zona generada (o se avisa de que falta)", z is None or ("ldap" in z), f"{z}")
    imprime(f"\nautotest: {'PASS' if not fallos else 'FAIL ' + str(fallos)}   (mecanica solamente; el arnes NO se ejecuto)")
    return 0 if not fallos else 1


SCRIPT = None   # se rellena en main(): dentro del contenedor el script llega por stdin y no hay __file__

if __name__ == "__main__":
    sys.exit(main())
