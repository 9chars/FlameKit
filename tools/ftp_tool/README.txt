FlameKit FTP tool
=================
Move this whole folder somewhere Claude cannot reach (for example your Documents folder), NOT inside
"C:\enshrouded mod shit". Then:

1. Double-click ftp_setup.cmd once and type the production server's FTP details (G-Portal's FTP page). The password
   is kept encrypted for your Windows user only.
2. When Claude says a server fix is ready, double-click upload.cmd. It uploads what Claude put in the outbox
   (C:\enshrouded mod shit\outbox) into the server's FlameKit folder, mod.json last, then fetches the server's log
   into the outbox so Claude can check the reload.

It never deletes anything on the server and never touches any other folder there.
