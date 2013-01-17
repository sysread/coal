import libevent as ev
import socket

# Create loop
loop = ev.Loop()

def test(event, fd, mask):
    print event, fd, mask
    event.disable()
    loop.exit()

# Connect to remote host
conn = socket.socket()
conn.connect(('www.google.com', 80))
conn.setblocking(False)

loop.watch(conn, ev.EV_READ, test)
conn.sendall('GET / HTTP/1.0\r\n\r\n')

loop.run()

exit()
