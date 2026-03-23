# uv-fzf

Use [uv](https://docs.astral.sh/uv/) with [fzf](https://junegunn.github.io/fzf/).

## Features

### Manage Python versions

Uses the `uv python` sub-command under the hood.

- Show the list of Python versions, installed or not.
- Highlighting a version shows its details in the right pane: its directory (the base directory name is obtained with `uv python dir`) and its size (obtained with `du -sh`). The directory is clickable to open it in the file manager.
- Selecting an installed version will ask to uninstall it.
- Selecting a non-installed version will ask to install it.

## Manage uv cache

Uses the `uv cache` sub-command under the hood.

TODO

### Manage uv tools

Uses the `uv tool` sub-command under the hood.

- Show the list of installed tools.
- Highlighting a tool shows its details in the right pane: its directory (the base directory name is obtained with `uv tool dir`).
- Selecting a tool will ask to uninstall it.
