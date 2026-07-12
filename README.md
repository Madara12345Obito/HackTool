# CTF Tools WEB2

Static single-page CTF tools reference.

## Open from GitHub Pages

Use the project root URL after GitHub Pages is enabled for the repository:

```text
https://madara12345obito.github.io/HackTool/
```

`index.html` redirects to `ctf_tools.html`, so the root URL works on any device.

## Open on the same Wi-Fi/LAN

Run this from the project folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\serve-lan.ps1 -Port 8080
```

Then open the printed `Network:` URL from another device on the same network.
