# VSCODE Config

A place to dump my VS Code setup so I can get it back later.

## Save (push)

Copies your computer setup into this folder. Overwrites files here, never changes live VS Code..

```bash
./push.sh
```

The script asks for your Windows username at runtime
(`Windows username:` prompt, or set `WIN_USERNAME` non-interactively).
It never hardcodes a username. Run it from this folder. Overwrites in this folder:

- `settings.json`
- `keybindings.json`
- `extensions.txt`
- `extensions.ver.txt` (list only, nothing installs from this)
- `extensions-wsl.txt`
- `snippets/` (if you have it)
- `profiles/` (only `settings.json`, `keybindings.json`, `snippets/`, `extensions.json` per profile)
- `machine-settings.json` (empty file if missing)
- `Default.code-profile` (if you have it)

## Restore (pull)

Copies this folder back into VS Code. Shows what it will touch, then asks `[y/N]`. Typing `N` stops it.

Warning: if you type `y`, it overwrites your live VS Code settings.

```bash
./pull.sh
```

The script asks for your Windows username at runtime
(`Windows username:` prompt, or set `WIN_USERNAME` non-interactively).
It only adds missing extensions, never removes extras.

## Manual copy (if scripts can't run)

Live Windows folder: `%APPDATA%\Code\User\` = `/mnt/c/Users/<USERNAME>/AppData/Roaming/Code/User/` (replace `<USERNAME>` with your Windows username; the scripts ask for it automatically)
This folder = repo root where `push.sh` lives.

| What         | Save: computer -> repo                                                                                                    | Restore: repo -> computer                                                |
| ------------ | ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| Settings     | `%APPDATA%\Code\User\settings.json` -> `settings.json`                                                                    | `settings.json` -> `%APPDATA%\Code\User\settings.json`                   |
| Keys         | `%APPDATA%\Code\User\keybindings.json` -> `keybindings.json`                                                              | `keybindings.json` -> `%APPDATA%\Code\User\keybindings.json`             |
| Snippets     | `%APPDATA%\Code\User\snippets\` -> `snippets\`                                                                            | `snippets\` -> `%APPDATA%\Code\User\snippets\`                           |
| Profiles     | `%APPDATA%\Code\User\profiles\` -> `profiles\` (only `settings.json`, `keybindings.json`, `snippets\`, `extensions.json`) | `profiles\` -> `%APPDATA%\Code\User\profiles\` (same 4 only)             |
| Profile file | `%APPDATA%\Code\User\Default.code-profile` -> `Default.code-profile`                                                      | `Default.code-profile` -> `%APPDATA%\Code\User\Default.code-profile`     |
| WSL settings | `~/.vscode-server/data/Machine/settings.json` -> `machine-settings.json`                                                  | `machine-settings.json` -> `~/.vscode-server/data/Machine/settings.json` |
| Win list     | Windows extension list -> `extensions.txt`                                                                                | `extensions.txt` -> install (see command below)                          |
| Version list | Windows extension list with versions -> `extensions.ver.txt` (check only)                                                 | Do not install from it                                                   |
| WSL list     | `~/.vscode-server/extensions/` names -> `extensions-wsl.txt`                                                              | `extensions-wsl.txt` -> install inside WSL (see command below)           |

Extensions (Windows, run in normal terminal):

```bash
cat extensions.txt | xargs -L1 code --install-extension
```

Extensions (WSL, run inside WSL):

```bash
cat extensions-wsl.txt | xargs -L1 code --install-extension
```

`Default.code-profile`: in VS Code go to Profiles > Import, pick the file. Export it the same way to save.

Fonts: `Monaspace Krypton Var` is installed on Windows itself, not copied here. Install it by hand on a new computer. Saved terminal paths (`powershell.exe`, `wsl.exe -d Ubuntu`) are Windows-only.
