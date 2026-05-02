# Insta360 Link 2 Pro — SDK reference

Hand-rolled UVC/DirectShow control code used while reverse-engineering the
Link 2 Pro PTZ. Kept as a reference, **not** part of the demo runtime.

| File | Platform | Purpose |
|------|----------|---------|
| `ptz_server_win.py`     | Windows | Working DirectShow `IAMCameraControl` PTZ server + ffmpeg MJPEG capture. Reference impl for `demo/camera.py`. |
| `ptz_server.py`         | macOS   | Original libusb-based PTZ HTTP server. |
| `probe_insta360_uvc.c`  | macOS   | Enumerate UVC interfaces / endpoints on the camera. |
| `uvc_ptz_probe.c`       | macOS   | Discover supported UVC PTZ control units. |
| `uvc_ptz_get.c` / `uvc_ptz_set.c` | macOS | Get/set raw UVC pan/tilt/zoom values. |
| `README-Windows.md` / `README-macOS.md` / `README-Ubuntu.md` | — | Per-platform setup notes. |

The demo (under `demo/`) only uses `ptz_server_win.py` as a code reference; it
does not import from this directory.
