import os
import subprocess
from dmgbuild import build_dmg

# Project settings
project_dir = subprocess.check_output(['git', 'rev-parse', '--show-toplevel']).decode('utf-8').strip()
project_name = "VideoDownloader"
app_path = os.path.join(project_dir, "build", f"{project_name}.app")
dmg_path = os.path.join(project_dir, "build", f"{project_name}.dmg")

# DMG settings
dmg_settings = {
    'format': 'UDBZ',
    'size': '100M',
    'files': [app_path],
    'symlinks': {'Applications': '/Applications'},
    'icon_locations': {
        f'{project_name}.app': (100, 100),
        'Applications': (300, 100)
    },
    'window_rect': ((100, 100), (400, 200)),
    'icon_size': 64,
    'text_size': 12,
}

def main():
    print(f"Creating DMG for {project_name}")
    print(f"App path: {app_path}")
    print(f"DMG path: {dmg_path}")

    if not os.path.exists(app_path):
        print(f"Error: .app file not found at {app_path}")
        print("Please build the .app file first using your Xcode build script.")
        return

    try:
        build_dmg(dmg_path, project_name, **dmg_settings)
        print(f"DMG created successfully: {dmg_path}")
    except Exception as e:
        print(f"Error creating DMG: {str(e)}")

if __name__ == "__main__":
    main()
