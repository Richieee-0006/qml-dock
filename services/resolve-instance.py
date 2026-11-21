#!/usr/bin/env python3
import sys
import os
import json
import glob
import configparser

INTERPRETERS = {
    "python", "python3", "python3.10", "python3.11", "python3.12", "python3.13", "python3.14",
    "bash", "sh", "zsh", "java", "node", "electron", "ruby", "perl", "gjs", "luajit", "lua"
}

def get_desktop_files():
    search_dirs = [
        os.path.expanduser("~/.local/share/applications"),
        os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
        "/var/lib/flatpak/exports/share/applications",
        "/usr/share/applications",
        "/usr/local/share/applications",
    ]
    files = []
    for d in search_dirs:
        if not os.path.isdir(d):
            continue
        for root, _, filenames in os.walk(d):
            for fn in filenames:
                if fn.endswith(".desktop"):
                    files.append(os.path.join(root, fn))
    return files


def find_icon_in_system(icon_name):
    """Resolve an icon name against pixmaps and hicolor/Flatpak icon dirs when theme lookup fails."""
    if not icon_name or icon_name.startswith("/") or icon_name.startswith("file://"):
        return icon_name
    base = os.path.splitext(icon_name)[0]
    exts = (".svg", ".png", ".xpm")
    pixmap_dirs = [
        "/usr/share/pixmaps",
        os.path.expanduser("~/.local/share/icons"),
    ]
    for pd in pixmap_dirs:
        for candidate in (icon_name, *(base + e for e in exts)):
            p = os.path.join(pd, candidate)
            if os.path.isfile(p):
                return p
    icon_roots = [
        os.path.expanduser("~/.local/share/icons/hicolor"),
        os.path.expanduser("~/.local/share/flatpak/exports/share/icons/hicolor"),
        "/var/lib/flatpak/exports/share/icons/hicolor",
        "/usr/share/icons/hicolor",
    ]
    for root_dir in icon_roots:
        if not os.path.isdir(root_dir):
            continue
        for size in ("scalable", "512x512", "256x256", "128x128", "64x64", "48x48"):
            for ext in exts:
                p = os.path.join(root_dir, size, "apps", base + ext)
                if os.path.isfile(p):
                    return p
    return icon_name

def find_desktop_by_criteria(desktop_files, script_paths, window_class, window_title):
    for df in desktop_files:
        try:
            cp = configparser.ConfigParser(interpolation=None)
            cp.read(df, encoding="utf-8")
            if not cp.has_section("Desktop Entry"):
                continue
            section = cp["Desktop Entry"]
            exec_line = section.get("Exec", "")
            wm_class = section.get("StartupWMClass", "")
            name = section.get("Name", "")
            icon = section.get("Icon", "")

            # Match StartupWMClass
            if window_class and wm_class and (wm_class.lower() == window_class.lower()):
                return name, icon, df

            # Match script path or basename in Exec
            for sp in script_paths:
                sp_clean = os.path.abspath(sp)
                sp_base = os.path.splitext(os.path.basename(sp))[0]
                if sp_clean in exec_line or (len(sp_base) > 2 and (sp_base in exec_line or f"/{sp_base}.desktop" in df)):
                    return name or sp_base, icon, df

            # Match window title to desktop entry Name
            if window_title and len(window_title) > 3:
                wt_low = window_title.lower()
                n_low = name.lower()
                if wt_low == n_low or wt_low.startswith(n_low) or n_low.startswith(wt_low):
                    return name, icon, df
        except Exception:
            continue
    return None, None, None

def find_local_icon(script_or_cwd):
    if not script_or_cwd:
        return None
    base_dir = script_or_cwd if os.path.isdir(script_or_cwd) else os.path.dirname(script_or_cwd)
    check_dirs = [base_dir]
    parent = os.path.dirname(base_dir)
    if parent and parent != base_dir:
        check_dirs.append(parent)

    for d in check_dirs:
        for p in ["icon.png", "icon.svg", "logo.png", "logo.svg"]:
            f = os.path.join(d, p)
            if os.path.isfile(f):
                return f
        for sub in ["assets", "icons", "res", "resources"]:
            sub_d = os.path.join(d, sub)
            if os.path.isdir(sub_d):
                for p in ["icon.png", "icon.svg", "logo.png", "logo.svg"]:
                    f = os.path.join(sub_d, p)
                    if os.path.isfile(f):
                        return f
    return None

def resolve_instance(pid, win_title="", win_class=""):
    try:
        pid = int(pid)
    except Exception:
        return {}

    cmdline = []
    cwd = ""
    exe = ""
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            cmdline = [a.decode("utf-8", errors="ignore") for a in f.read().split(b"\0") if a]
    except Exception:
        pass
    try:
        cwd = os.readlink(f"/proc/{pid}/cwd")
    except Exception:
        pass
    try:
        exe = os.readlink(f"/proc/{pid}/exe")
    except Exception:
        pass

    name = win_title or win_class or "App"
    icon = None

    # Check 1: Minecraft / PrismLauncher / MultiMC
    is_minecraft = (
        "minecraft" in (win_class or "").lower() or
        "minecraft" in (win_title or "").lower() or
        any("prismlauncher" in a.lower() or "minecraft" in a.lower() for a in cmdline)
    )
    if is_minecraft:
        instance_dir = cwd
        if os.path.basename(instance_dir) in ["minecraft", ".minecraft"]:
            instance_dir = os.path.dirname(instance_dir)
        name = os.path.basename(instance_dir)

        for c in [
            os.path.join(cwd, "icon.png"),
            os.path.join(instance_dir, "icon.png"),
            os.path.join(instance_dir, "minecraft", "icon.png"),
            os.path.join(instance_dir, ".minecraft", "icon.png")
        ]:
            if os.path.isfile(c):
                icon = c
                break

        if not icon:
            cfg_path = os.path.join(instance_dir, "instance.cfg")
            if os.path.isfile(cfg_path):
                icon_key = None
                try:
                    with open(cfg_path, "r", encoding="utf-8", errors="ignore") as f:
                        for line in f:
                            line = line.strip()
                            if line.startswith("iconKey="):
                                icon_key = line.split("=", 1)[1]
                            elif line.startswith("name="):
                                inst_name = line.split("=", 1)[1].strip()
                                if inst_name:
                                    name = inst_name
                except Exception:
                    pass
                if icon_key:
                    for m in glob.glob(f"{instance_dir}/{icon_key}*") + glob.glob(os.path.expanduser(f"~/.local/share/PrismLauncher/icons/{icon_key}*")):
                        if os.path.isfile(m):
                            icon = m
                            break

    # Check 2: Script or app running under interpreter / wrapper
    if not icon:
        script_args = []
        for arg in cmdline[1:]:
            if arg.startswith("-") or not arg:
                continue
            if os.path.exists(arg) or "/" in arg or arg.endswith((".py", ".sh", ".js", ".jar", ".rb", ".lua")):
                script_args.append(arg)

        desktop_files = get_desktop_files()
        d_name, d_icon, d_path = find_desktop_by_criteria(desktop_files, script_args, win_class, win_title)
        if d_name:
            name = d_name
        if d_icon:
            icon = d_icon

        if not icon and script_args:
            for sp in script_args:
                local_icon = find_local_icon(sp)
                if local_icon:
                    icon = local_icon
                    break

        if not icon and cwd:
            local_icon = find_local_icon(cwd)
            if local_icon:
                icon = local_icon

    if icon and not icon.startswith(("/", "~", "file://")):
        icon = find_icon_in_system(icon)

    if icon and (icon.startswith("/") or icon.startswith("~")):
        icon = os.path.expanduser(icon)
        if not icon.startswith("file://"):
            icon = "file://" + icon

    return {
        "pid": pid,
        "name": name,
        "icon": icon or ""
    }

if __name__ == "__main__":
    if len(sys.argv) > 1:
        pid = sys.argv[1]
        win_title = sys.argv[2] if len(sys.argv) > 2 else ""
        win_class = sys.argv[3] if len(sys.argv) > 3 else ""
        result = resolve_instance(pid, win_title, win_class)
        print(json.dumps(result))
    else:
        print(json.dumps({}))
