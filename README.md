# RAM Free

Omarchy bar widget: a ring that shows how much memory is in use. Click it to
open a popup, then click a depth tile (1-5) to free RAM.

| Depth | Name     | Needs root | What it does |
|-------|----------|------------|--------------|
| 1     | Tidy     | no  | Reclaims 20% of your session's file cache |
| 2     | Light    | no  | Reclaims 10% of session memory (cold pages are compressed into zram) |
| 3     | Standard | yes | Light, plus drops the kernel page, dentry and inode caches |
| 4     | Deep     | yes | Reclaims 25% of session memory, drops caches, compacts RAM |
| 5     | Max      | yes | Reclaims 50% of session and 25% of system services memory, drops caches, compacts |

Depths 1-2 write to your own cgroup's `memory.reclaim`, so they need no
password. Depths 3-5 call a small root helper through `pkexec`. Swap reclaim
is capped at half of the free swap.

```sh
make install                 # plugin -> ~/.config/omarchy/plugins/arch.ramfree, CLI -> ~/.local/bin/ramfree
sudo make install-helper     # root helper + polkit policy (depths 3-5, no password prompt)
ramfree run 3                # same thing from a terminal; prints JSON
omarchy-shell arch.ramfree run 2   # from a keybinding; sends a notification
```

Popup keys: `1`-`5` run a depth, `←`/`→` + `Enter` pick one, `Esc` closes.
Middle-clicking the bar ring reruns the last selected depth.

Set `"showPercent": true` on the widget entry in `~/.config/omarchy/shell.json`
to show the percentage next to the ring.

Freeing memory only makes room. Apps read dropped caches back from disk, and
reclaimed pages come back from zram when they are next used, so higher depths
can cause brief slowdowns right after a run.

`make uninstall` and `sudo make uninstall-helper` remove everything.
