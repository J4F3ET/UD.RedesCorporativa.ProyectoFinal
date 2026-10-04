#!/usr/bin/env python3
"""Sonda LDAP minima y sin dependencias: bind anonimo + busqueda al rootDSE.

AD (Samba) no permite busquedas anonimas salvo al rootDSE (base "", scope base): a diferencia de
OpenLDAP, un bind anonimo que si tenga exito no basta para demostrar que el directorio "funciona" por
LDAP, porque una busqueda normal (subtree, cualquier OU) daria "Insufficient access". Este script hace
un bind simple anonimo (nombre y clave vacios) y, si el bind da exito, busca el rootDSE pidiendo el
atributo namingContexts (publico incluso sin autenticar). Protocolo LDAP crudo (BER), sin python-ldap
ni otras dependencias, para poder ejecutarse dentro de contenedores efimeros minimos (ver
verificar_arquitectura.py:bloque_consolidado, que invoca este script tal cual, sin duplicarlo).

Uso: ldapprobe.py HOST PUERTO   (p. ej. HOST_IP y LDAP_PORT; o la IP fija del DC y 389, dentro de la red)
"""
import socket
import sys



def _tlv(tag, valor):
    n = len(valor)
    if n < 0x80:
        cab = bytes([tag, n])
    else:
        b = n.to_bytes((n.bit_length() + 7) // 8, "big")
        cab = bytes([tag, 0x80 | len(b)]) + b
    return cab + valor


def _entero(tag, v):
    return _tlv(tag, bytes([v]))   # valores 0-127: suficiente para este script


def _leer_mensaje(sock):
    """Lee un LDAPMessage BER completo (SEQUENCE) de un socket TCP y devuelve sus bytes crudos."""
    cab = b""
    while len(cab) < 2:
        trozo = sock.recv(2 - len(cab))
        if not trozo:
            raise ConnectionError("conexion cerrada antes de la cabecera")
        cab += trozo
    n = cab[1]
    largo_extra = b""
    if n & 0x80:
        k = n & 0x7F
        while len(largo_extra) < k:
            trozo = sock.recv(k - len(largo_extra))
            if not trozo:
                raise ConnectionError("conexion cerrada leyendo la longitud")
            largo_extra += trozo
        n = int.from_bytes(largo_extra, "big")
    cuerpo = b""
    while len(cuerpo) < n:
        trozo = sock.recv(n - len(cuerpo))
        if not trozo:
            raise ConnectionError("conexion cerrada mientras se leia el mensaje")
        cuerpo += trozo
    return cab + largo_extra + cuerpo


def _analiza(mensaje):
    """(tag_del_protocolOp, indice_donde_empieza_su_valor, longitud_de_su_valor)."""
    i = 2 if mensaje[1] < 0x80 else 2 + (mensaje[1] & 0x7F)
    largo_id = mensaje[i + 1]
    i += 2 + largo_id   # salta la SEQUENCE externa + el INTEGER messageID
    tag_op = mensaje[i]
    largo_op = mensaje[i + 1]
    j = i + 2
    if largo_op & 0x80:
        k = largo_op & 0x7F
        largo_op = int.from_bytes(mensaje[j:j + k], "big")
        j += k
    return tag_op, j, largo_op


def _result_code(mensaje, j):
    """resultCode ENUMERATED: primer campo de un LDAPResult (BindResponse y SearchResultDone lo reusan).
    Asume resultCode < 128 (siempre cierto: el mayor definido es 123)."""
    return mensaje[j + 2]


def main():
    if len(sys.argv) != 3 or not sys.argv[2].isdigit():
        print(__doc__.strip().splitlines()[-1])
        return 2
    HOST, PUERTO = sys.argv[1], int(sys.argv[2])
    try:
        s = socket.create_connection((HOST, PUERTO), timeout=5)
    except OSError as e:
        print(f"TCP: FALLO al conectar a {HOST}:{PUERTO}: {e}")
        return 1
    try:
        # 1) BindRequest anonimo: version=3, name="", authentication simple=""
        bind_req = _tlv(0x60, _entero(0x02, 3) + _tlv(0x04, b"") + _tlv(0x80, b""))
        s.sendall(_tlv(0x30, _entero(0x02, 1) + bind_req))
        m = _leer_mensaje(s)
        tag, j, _ = _analiza(m)
        if tag != 0x61:
            print(f"BIND anonimo: FALLO (PDU inesperada, tag={tag:#x})")
            return 1
        rc = _result_code(m, j)
        print(f"BIND anonimo: {'OK' if rc == 0 else 'FALLO'} (BindResponse resultCode={rc})")
        if rc != 0:
            return 1

        # 2) SearchRequest al rootDSE: base="", scope=base(0), filtro (objectClass=*), atributo namingContexts
        filtro = _tlv(0x87, b"objectClass")   # [7] present
        atributos = _tlv(0x30, _tlv(0x04, b"namingContexts"))
        busqueda = _tlv(0x63, _tlv(0x04, b"") + _entero(0x0A, 0) + _entero(0x0A, 0)
                         + _entero(0x02, 0) + _entero(0x02, 0) + b"\x01\x01\x00" + filtro + atributos)
        s.sendall(_tlv(0x30, _entero(0x02, 2) + busqueda))

        entradas, rc_busqueda = 0, None
        while True:
            m = _leer_mensaje(s)
            tag, j, _ = _analiza(m)
            if tag == 0x64:   # SearchResultEntry
                entradas += 1
                continue
            if tag == 0x65:   # SearchResultDone
                rc_busqueda = _result_code(m, j)
                break
            print(f"BUSQUEDA rootDSE: FALLO (PDU inesperada, tag={tag:#x})")
            return 1

        ok = rc_busqueda == 0 and entradas >= 1
        print(f"BUSQUEDA rootDSE: {'OK' if ok else 'FALLO'} (entradas={entradas} resultCode={rc_busqueda})")
        print(f"SONDA LDAP (samba-ad): {'PASS' if ok else 'FAIL'}")
        return 0 if ok else 1
    except (ConnectionError, OSError) as e:
        print(f"SONDA LDAP (samba-ad): FAIL (error de conexion: {e})")
        return 1
    finally:
        s.close()


if __name__ == "__main__":
    sys.exit(main())
