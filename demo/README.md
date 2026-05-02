# walk-talk demo (Windows)

End-to-end Insta360 Link 2 Pro × LLM agent demo. See
`docs/superpowers/specs/2026-05-02-link2pro-windows-demo-design.md` for design.

## Prereqs
- Windows 10/11
- Insta360 Link 2 Pro plugged in (DirectShow name "Insta360 Link 2")
- ffmpeg on PATH (or `C:\ffmpeg\bin\ffmpeg.exe`)
- Network access to `http://100.99.139.20:18141` (Tailscale)

## Run
```
pip install -r demo/requirements.txt
python -m demo.server
```
Open http://127.0.0.1:8788/

## Tests
```
pytest demo/tests -v
```
