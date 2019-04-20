nix-cntr-socket-over-socket

I tried to make an environment for myself where I can mess with cntr more easily.
The goal is to forward network sockets over unix sockets to debug a java application running inside a Nix sandbox.

Enter the environment with `nix-shell -E "(import ./test.nix {}).shell"`.
Inner shells are also started with this mechanism.
Exit with `seppuku` in any environment shell (kills the tmux server)
Reload shellHooks via `reloadShell` (enters new shell via exec)

See various other convenience functions in `shellHooks` in `test.nix`.
