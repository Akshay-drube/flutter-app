from flask import Flask, Response, jsonify
from flask_sock import Sock
from picamera2 import Picamera2
from picamera2.encoders import MJPEGEncoder
from picamera2.outputs import FileOutput
import io
import threading
import subprocess
import json
import time

app = Flask(__name__)
sock = Sock(app)

# ── Camera setup ───────────────────────────────────────────────────────────────
picam2 = Picamera2()
picam2.configure(picam2.create_video_configuration(
    main={"size": (640, 480)}
))

class StreamOutput(io.BufferedIOBase):
    def __init__(self):
        self.frame = None
        self.condition = threading.Condition()

    def write(self, buf):
        with self.condition:
            self.frame = buf
            self.condition.notify_all()

output = StreamOutput()
picam2.start_recording(MJPEGEncoder(), FileOutput(output))

# ── Robot state ────────────────────────────────────────────────────────────────
_robot_running = False
_boundary      = []

# ── Signal helper ──────────────────────────────────────────────────────────────
def get_signal():
    try:
        result = subprocess.check_output(
            ['iw', 'dev', 'wlan0', 'station', 'dump'],
            stderr=subprocess.STDOUT,
            timeout=3
        ).decode('utf-8')

        lines = result.split('\n')

        def get_value(keyword):
            for line in lines:
                if keyword in line:
                    return line.split(':', 1)[1].strip()
            return 'unknown'

        tx_bitrate = get_value('tx bitrate')
        try:
            mbits = float(tx_bitrate.split(' ')[0])
        except:
            mbits = 0.0

        if mbits >= 65:   distance = "Very Close (1-2m)"
        elif mbits >= 54: distance = "Close (3-5m)"
        elif mbits >= 36: distance = "Medium (5-10m)"
        elif mbits >= 18: distance = "Far (10-20m)"
        else:             distance = "Very Far (20m+)"

        return {"tx_bitrate": tx_bitrate, "mbits": mbits, "distance": distance}
    except Exception as e:
        return {"tx_bitrate": "unknown", "mbits": 0.0, "distance": "Unknown"}

def build_payload():
    return {
        "status":  "connected",
        "running": _robot_running,
        "signal":  get_signal(),
        "gps": {
            "latitude":   10.0261,
            "longitude":  76.3083,
            "altitude":   0.0,
            "location":   "Kerala, India",
            "gps_status": "simulated"
        },
        "battery": {
            "percentage": 82,
            "voltage":    7.4,
            "charging":   False
        }
    }

# ── MJPEG stream ───────────────────────────────────────────────────────────────
def generate_frames():
    while True:
        with output.condition:
            output.condition.wait(timeout=5)
            frame = output.frame
        if frame:
            yield (
                b'--frame\r\n'
                b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n'
            )

# ── HTTP routes ────────────────────────────────────────────────────────────────
@app.route('/stream')
def stream():
    return Response(
        generate_frames(),
        mimetype='multipart/x-mixed-replace; boundary=frame'
    )

@app.route('/status')
def status():
    return jsonify({"status": "online", "name": "Pi_Robot"})

@app.route('/data')
def data():
    return jsonify(build_payload())

# ── WebSocket ──────────────────────────────────────────────────────────────────
@sock.route('/ws')
def websocket(ws):
    global _robot_running, _boundary
    print('[WS] Client connected')

    stop_event = threading.Event()

    def sender():
        while not stop_event.is_set():
            try:
                ws.send(json.dumps(build_payload()))
                time.sleep(0.5)
            except Exception:
                break

    t = threading.Thread(target=sender, daemon=True)
    t.start()

    while True:
        try:
            msg = ws.receive(timeout=30)
            if msg is None:
                break
            cmd = json.loads(msg)
            command = cmd.get('command')

            if command == 'start':
                _robot_running = True
                print('[WS] Robot STARTED')

            elif command == 'stop':
                _robot_running = False
                print('[WS] Robot STOPPED')

            elif command == 'set_boundary':
                _boundary = cmd.get('boundary', [])
                count = len(_boundary)
                print(f'[WS] Boundary set — {count} points')
                for i, pt in enumerate(_boundary):
                    print(f'  {i+1}. lat={pt["lat"]:.6f}, lng={pt["lng"]:.6f}')
                ws.send(json.dumps({
                    "status": "connected",
                    "boundary_ack": True,
                    "boundary_count": count
                }))

        except Exception as e:
            print(f'[WS] Error: {e}')
            break

    stop_event.set()
    print('[WS] Client disconnected')

# ── Main ───────────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, threaded=True)