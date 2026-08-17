# dev-environment-setup

Personal Arch Linux dev environment bootstrapper. Installs tools via pacman/yay and GitHub releases, configures SSH/Git signing, tmux, kitty, Neovim, and custom shell scripts.

## Entrypoints

- `setup.sh` — copies `my-scripts/` to `~/.local/bin`, registers PATH + opener functions in `.bashrc`, runs script suites
  - No flag: safe mode — runs only `github_setup.sh` and `sync_config.sh`
  - `--full`: runs all scripts under `scripts/`, then `configure-low-memory-jvm.sh` (skipped if `java` not on PATH)
- `bash test_setup.sh` — tests block registration, opener functions, idempotency, PATH injection

## Scripts (run by `setup.sh` in order)

1. `install_prerequisites.sh` — zip, unzip, yay (AUR helper)
2. `install_requirements.sh` — packages from `requirements.txt`
3. `install_github_releases.sh` — latest GitHub releases from `github_requirements.txt`
4. `setup_languages.sh` — Zig, SDKMAN (Java), NVM (Node), Go, golangci-lint
5. `github_setup.sh` — SSH key gen, GitHub auth test, Git commit signing (SSH)
6. `setup_tmux.sh` — tmux config, kitty `confirm_os_window_close 0`, tmux auto-start in `.bashrc`
7. `sync_config.sh` — copies `config/nvim/` → `~/.config/nvim/`

## Constraints

- **Arch Linux only** — uses `pacman` + `yay`. Other distros will fail on `requirements.txt`.

## Opener scripts

Any file in `my-scripts/` with `# opener: cd` within the first 3 lines gets special treatment by `setup.sh` — it becomes a bash function in `.bashrc` that `cd`s to the script's output directory. Current openers: `gc` (git clone + cd), `np` (new project scaffold), `op` (fzf project/config picker).

## Key files

- `requirements.txt` — AUR/official packages (one per line, `#` comments)
- `github_requirements.txt` — `owner/repo` entries for GitHub release downloads
- `config/nvim/` — Neovim configuration (managed separately)
