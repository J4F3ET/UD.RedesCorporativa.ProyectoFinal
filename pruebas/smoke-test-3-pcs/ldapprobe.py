import socket,sys
s=socket.create_connection(("10.10.99.10",389),timeout=5)
s.sendall(bytes.fromhex("300c020101600702010304008000"))
d=s.recv(64)
print("TCP OK; respuesta LDAP BindResponse" if len(d)>4 and d[0]==0x30 and 0x61 in d[:8] else "TCP OK; respuesta inesperada: "+d.hex())
