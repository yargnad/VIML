# VIML: Compile From Source

This repository contains a helper script to compile Python and FFmpeg from source and set up a small project scaffold.

Files of interest

- `compile_from_source.sh` — main installation and build script (interactive).

Prerequisites

- WSL or Linux with sudo access
- Enough disk space and time to compile large projects (Python/FFmpeg)
- `git`, `wget`, `make`, compilers (the script installs build tools)

Quick usage

1. Make the script executable:

```bash
chmod +x compile_from_source.sh
```

2. Run the script:

```bash
./compile_from_source.sh
```

Security

- Do not commit personal access tokens. When the script prompts for a Hugging Face token or Git credentials, enter them interactively.
- Prefer SSH authentication for private GitHub repos (set `PROJECT_REPO` to `git@github.com:owner/repo.git`).

Development

- Lint with ShellCheck locally:

```bash
shellcheck -x compile_from_source.sh
```

CI

A GitHub Actions workflow is included to run ShellCheck on push and pull requests.

Support

If you want me to create the remote repository on GitHub and push the initial commit, tell me and I can prepare the commands (or use the GitHub CLI if you have it configured).
