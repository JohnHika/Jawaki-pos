import hashlib, json, os, subprocess, sys, tempfile

source, target = sys.argv[1], sys.argv[2]


def gh(*args):
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


for release in json.load(open("releases.json", encoding="utf-8")):
    tag = release["tag"]
    with tempfile.TemporaryDirectory() as work:
        gh("release", "download", tag, "-R", source, "-D", work)
        files = []
        for asset in release["assets"]:
            path = os.path.join(work, asset["name"])
            data = open(path, "rb").read()
            if len(data) != asset["size"]:
                raise SystemExit(f"{tag}/{asset['name']}: size differs")
            if asset["digest"] and "sha256:" + hashlib.sha256(data).hexdigest() != asset["digest"]:
                raise SystemExit(f"{tag}/{asset['name']}: checksum differs")
            files.append(path)
        notes = os.path.join(work, ".notes.md")
        open(notes, "w", encoding="utf-8").write(release["body"])
        gh("release", "create", tag, *files, "-R", target, "--verify-tag",
           "--title", release["name"], "--notes-file", notes,
           "--latest=" + ("true" if release["latest"] else "false"))
        print("copied", tag, flush=True)
