"""Tiny adb driver for visual QA on the emulator. Usage: python qa.py <command> [args]
Commands:  shot NAME | tap X Y | swipe X1 Y1 X2 Y2 [ms] | text STR | key CODE | back | tab N | sleep S
Screenshots land in %TEMP%/aca_qa/NAME.png (1080x2340)."""
import os, subprocess, sys, time

ADB = r"C:\Android\platform-tools\adb.exe"
DEV = os.environ.get("QA_DEVICE", "emulator-5554")
OUT = os.path.join(os.environ.get("TEMP", "."), "aca_qa")
os.makedirs(OUT, exist_ok=True)
TABS = {0: 108, 1: 324, 2: 540, 3: 756, 4: 972}  # bottom-nav x centres on a 1080-wide screen


def adb(*a, capture=False):
    cmd = [ADB, "-s", DEV, *a]
    if capture:
        return subprocess.run(cmd, capture_output=True).stdout
    subprocess.run(cmd, check=False)


def shot(name):
    data = adb("exec-out", "screencap", "-p", capture=True)
    p = os.path.join(OUT, name + ".png")
    open(p, "wb").write(data)
    print(p)


if __name__ == "__main__":
    c, a = sys.argv[1], sys.argv[2:]
    if c == "shot": shot(a[0])
    elif c == "tap": adb("shell", "input", "tap", a[0], a[1])
    elif c == "swipe": adb("shell", "input", "swipe", *a[:4], a[4] if len(a) > 4 else "350")
    elif c == "text": adb("shell", "input", "text", a[0].replace(" ", "%s").replace("!", "\\!"))
    elif c == "key": adb("shell", "input", "keyevent", a[0])
    elif c == "back": adb("shell", "input", "keyevent", "4")
    elif c == "tab": adb("shell", "input", "tap", str(TABS[int(a[0])]), "2200")
    elif c == "sleep": time.sleep(float(a[0]))
