# bird

A fully statically-linked `bird`/`birdc` build, packaged as a minimal `scratch` container image
(`ghcr.io/slipmesh/bird`).

## Why this exists

[slipmesh/operators](https://github.com/slipmesh/operators)' `router` operator renders BIRD's
config and talks to its control socket, but doesn't build BIRD itself - it currently installs
BIRD from Alpine's `bird2` package inside the same container. This repo exists to run BIRD as a
separate sidecar container in the same pod instead:

- BIRD's own release cadence and build (a C project) is decoupled from `router`'s (a Rust
  project) - bumping one doesn't require rebuilding/retesting the other.
- Least-privilege capabilities: `NET_RAW`/`NET_BIND_SERVICE` (BIRD's raw OSPF socket, BGP's
  privileged port) only need to be granted to this container, not to the Rust operator's as well.
- `router`'s own image can go back to a minimal/scratch base like `mesh`/`roadwarriors`/`nftables`
  already do, instead of needing a real Alpine userland just to hold a dynamically-linked `bird2`
  package.

The two containers share a pod-scoped `emptyDir` volume for the config file and control socket -
see [slipmesh/operators#8](https://github.com/slipmesh/operators/issues/8) for the full design.

## What's in the image

Just two binaries at `/`: `bird` (the daemon) and `birdc` (the interactive control-socket client,
kept for manual `kubectl exec` debugging - `router` itself talks to the control socket directly,
not through `birdc`).

Built from `github.com/CZ-NIC/bird`, an official mirror of the real upstream
(`gitlab.nic.cz/labs/bird`) maintained by the same organization - verified byte-identical (same
commit per tag). Used instead of cloning gitlab.nic.cz directly because that 403s from GitHub
Actions' own IP range specifically, separately from
`bird.nic.cz`'s tarball downloads 403ing unconditionally for everyone. Pinned to a tag (see
`BIRD_REV` in the `Dockerfile`), currently `v2.19.2` - the latest 2.x release, and the version
verified against the RFC 8950 (extended next-hop) underlay redesign tracked in operators#8.

`--disable-libssh` at configure time: BIRD's only use for libssh is RPKI-over-SSH transport, which
this project's BIRD config never uses. `ncurses-static`/`readline-static` (Alpine packages) let
`birdc`'s interactive line editing link statically instead of pulling in `libncursesw.so`/
`libreadline.so`. The build also runs BIRD's own unit test suite (`make check`) and fails loudly
if either binary comes out dynamically linked (checked via `file`, not `ldd` - musl's static-PIE
binaries carry a `PT_INTERP` pointing at `ld-musl-*.so.1` for self-relocation, which `ldd`
misreports as a real dynamic dependency even though the binary runs standalone; verified by
actually running the built `scratch` image's binaries).

## Patches

`patches/` carries modifications on top of vanilla upstream BIRD, applied via `git apply` during
the Docker build (see `Dockerfile`) - disclosed here per GPLv2 §2(a)'s requirement to mark changed
files and the date of the change:

- `0001-wait-for-config-file-to-appear.patch` (2026-08-07, `sysdep/unix/main.c`): on startup, if
  the config file doesn't exist yet, BIRD normally calls `die()` immediately. This patch instead
  logs once and polls until it appears, then proceeds normally - written for exactly this repo's
  own sidecar use case, where `router` (a separate container in the same pod) writes the config
  to a shared `emptyDir` and may not have done so yet by the time this container starts. Verified:
  builds cleanly, and a patched `bird` given a missing config waits (confirmed via
  `/proc/<pid>/wchan` and a live `birdc` connection after the file appeared) instead of exiting.

## Versioning

Tags (`vX.Y.Z`) follow this repo's own release cadence, independent of `slipmesh/operators`'
version - bumping BIRD here doesn't imply a `router` release, and vice versa.

## License

BIRD itself is GPLv2-or-later (see `COPYING`, copied verbatim from the FSF). This repo's own
additions (`Dockerfile`, CI, and the patches in `patches/`) are distributed under the same terms,
as required for a modified GPL work. `slipmesh/operators` and `slipmesh/helm` are separate
programs communicating with BIRD over a Unix socket/subprocess boundary, not linked with it, and
keep their own MIT/Apache-2.0 licensing unaffected by this.
