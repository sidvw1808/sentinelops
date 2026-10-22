# Installation (Ubuntu and WSL2)

SentinelOps is a set of Bash scripts. There is nothing to compile, and it runs
as a normal user.

## 1. Check prerequisites

```bash
bash --version        # needs 4.4 or newer (Ubuntu 18.04+ ships 4.4+)
```

The core tools (`awk`, `grep`, `sed`, `ps`, `df`, `curl`) are present on a
standard Ubuntu install. If any are missing:

```bash
sudo apt update
sudo apt install gawk grep sed procps coreutils curl
```

Development tools (needed only to run the linter and tests):

```bash
sudo apt install shellcheck python3
```

## 2. Get the code

```bash
git clone <repository-url> sentinelops
cd sentinelops
```

## 3. Configure

```bash
cp config/sentinelops.conf.example config/sentinelops.conf
"${EDITOR:-nano}" config/sentinelops.conf
./sentinelops.sh validate-config
```

`config/sentinelops.conf` is ignored by Git, so your local settings stay out
of the repository.

## 4. Verify

```bash
./sentinelops.sh deps
tests/run_tests.sh
```

## 5. Optional: put it on your PATH

```bash
mkdir -p ~/.local/bin
ln -s "$PWD/sentinelops.sh" ~/.local/bin/sentinelops
sentinelops version
```

The script follows the symlink to find its own directory (this uses GNU
`readlink -f`, standard on Ubuntu).

## WSL2 notes

- **systemd may be off.** Older WSL setups do not run systemd. Then
  `systemctl` exists but cannot reach a service manager, and the services
  module will report `UNKNOWN` instead of guessing. `./sentinelops.sh deps`
  tells you which case you are in. To enable systemd in WSL, add to
  `/etc/wsl.conf` and restart WSL (`wsl --shutdown` from Windows):

  ```ini
  [boot]
  systemd=true
  ```

- **Keep the repository on the Linux filesystem** (e.g. `~/projects`), not
  under `/mnt/c`. Windows drives are slower and may change file permissions
  and line endings.
- **Line endings.** If you edit files from Windows, make sure your editor uses
  LF. The repository's `.gitattributes` forces LF for scripts; the config
  loader also accepts CRLF config files.
- **Metrics describe the WSL VM**, not the whole Windows host: CPU and memory
  figures come from the lightweight VM that WSL2 runs.
