import os
import sys
import zipfile
import json
import re

def main():
    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    dist_dir = os.path.dirname(repo_root)
    zip_output = os.path.join(dist_dir, "1-Click-DLSS5-v3.0.2.zip")

    print(f"=== 1-Click DLSS 5 Release Packager (v3.0.2) ===")
    print(f"Source: {repo_root}")
    print(f"Destination: {zip_output}")

    # 1. Sanity Checks
    log_file = os.path.join(repo_root, "core", "1-Click-DLSS5.log")
    if os.path.exists(log_file) and os.path.getsize(log_file) > 0:
        print("[WARN] Truncating core/1-Click-DLSS5.log to 0 bytes before packaging...")
        open(log_file, "w").close()

    config_file = os.path.join(repo_root, "core", "assets", "config.json")
    if os.path.exists(config_file):
        with open(config_file, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        if cfg.get("LastSelectedGamePath") or cfg.get("CustomGamePaths"):
            print("[WARN] Resetting core/assets/config.json to clean defaults...")
            cfg["LastSelectedGamePath"] = ""
            cfg["CustomGamePaths"] = []
            with open(config_file, "w", encoding="utf-8") as f:
                json.dump(cfg, f, indent=4)

    cache_file = os.path.join(repo_root, "core", "assets", "games_cache.json")
    if os.path.exists(cache_file):
        with open(cache_file, "r", encoding="utf-8") as f:
            cache = json.load(f)
        if len(cache) > 0:
            print("[WARN] Resetting core/assets/games_cache.json to empty list...")
            with open(cache_file, "w", encoding="utf-8") as f:
                json.dump([], f, indent=4)

    # 2. Shader Checks
    shader_dir = os.path.join(repo_root, "core", "payload", "feeder", "shaders")
    forbidden = ["FXAA.fx", "FXAA.fxh", "SMAA.fx", "SMAA.fxh"]
    for fb in forbidden:
        p = os.path.join(shader_dir, fb)
        if os.path.exists(p):
            print(f"[ERROR] Forbidden shader {fb} still present! Removing...")
            os.remove(p)

    # 3. Packaging
    exclude_dirs = {".git", ".vs", ".vscode", "scratch", "bin", "obj", "__pycache__"}
    exclude_files = {
        "1-Click-DLSS5.log",
        ".gitattributes",
        ".gitignore",
        "desktop.ini",
        "Thumbs.db"
    }

    if os.path.exists(zip_output):
        os.remove(zip_output)

    added_files = []
    with zipfile.ZipFile(zip_output, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zipf:
        for root, dirs, files in os.walk(repo_root):
            dirs[:] = [d for d in dirs if d not in exclude_dirs]
            for file in files:
                if file in exclude_files or file.endswith(".tmp") or file.endswith(".zip"):
                    continue
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, repo_root)
                
                # Archive name has folder prefix 1-Click-DLSS5/
                archive_name = ("1-Click-DLSS5/" + rel_path).replace("\\", "/")
                zipf.write(full_path, archive_name)
                added_files.append(archive_name)

    print(f"\n[OK] Release zip generated: {zip_output}")
    print(f"[OK] Total files packaged: {len(added_files)}")
    print(f"[OK] Package size: {os.path.getsize(zip_output):,} bytes ({os.path.getsize(zip_output)/(1024*1024):.2f} MB)")

    # 4. Post-Packaging Audit
    print("\n=== Post-Packaging Security & Privacy Audit ===")
    leak_patterns = [
        re.compile(r"Luis\s+Eduardo", re.IGNORECASE),
        re.compile(r"C:\\OneDrive", re.IGNORECASE),
        re.compile(r"E:\\JOGOS", re.IGNORECASE),
        re.compile(r"FreshWomen", re.IGNORECASE)
    ]
    leaks_found = 0
    with zipfile.ZipFile(zip_output, "r") as zipf:
        for info in zipf.infolist():
            # Check text files for personal data
            if any(info.filename.endswith(ext) for ext in [".json", ".txt", ".md", ".log", ".ini", ".cfg", ".conf"]):
                content = zipf.read(info.filename).decode("utf-8", errors="ignore")
                for pat in leak_patterns:
                    if pat.search(content):
                        print(f"[FAIL] Privacy leak in {info.filename}: matched {pat.pattern}")
                        leaks_found += 1

    if leaks_found > 0:
        print(f"\n[ERROR] Audit failed with {leaks_found} potential leaks!")
        sys.exit(1)
    else:
        print("[PASS] Audit complete! Zero personal data, zero developer logs found in zip.")

if __name__ == "__main__":
    main()
