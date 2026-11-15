FlameKit FTP tool
=================
Lives in C:\enshrouded mod shit\release\FlameKit FTP tool (owner, 2026-11-15: Claude may upload to the production
server). Then:

1. Double-click ftp_setup.cmd once and type the production server's FTP details (G-Portal's FTP page). The password
   is kept encrypted for your Windows user only (ftp_password.dat); Claude never opens it.
2. Uploads: Claude asks the restart helper (keep restart_watch.cmd open) with an 'upload' request, or you double-click
   upload.cmd yourself. It uploads what is in the outbox (C:\enshrouded mod shit\outbox) into the server's FlameKit
   folder, mod.json last, then fetches the server's logs into C:\enshrouded mod shit\production_stable_logs.

It never deletes anything on the server and never touches any other folder there.
