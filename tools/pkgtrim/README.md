# pkgtrim

Fast, read-only Pacman dependency auditor for this machine. It reads
`/var/lib/pacman/local` directly and reports debug packages, unused versioned
Electron runtimes, and dependency-installed packages with no reverse users.

It never installs or removes packages. Review candidates with Pacman before
changing the system.

```bash
cargo build --release
install -Dm755 target/release/pkgtrim ~/.local/bin/pkgtrim
pkgtrim
```

Packages used by local scripts but invisible to Pacman's dependency graph belong
in `~/.config/pkgtrim/protect`, one package name per line.
