# bird

A fully statically-linked `bird`/`birdc` build, packaged as a minimal `scratch` container image
(`ghcr.io/slipmesh/bird`).

## Why this exists

The `router` operator this was built for renders BIRD's
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

The two containers share a pod-scoped `emptyDir` volume for the config file and the control
socket.

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
verified against the RFC 8950 (extended next-hop) underlay redesign.

`--disable-libssh` at configure time: BIRD's only use for libssh is RPKI-over-SSH transport, which
this project's BIRD config never uses. `ncurses-static`/`readline-static` (Alpine packages) let
`birdc`'s interactive line editing link statically instead of pulling in `libncursesw.so`/
`libreadline.so`. The build also runs BIRD's own unit test suite (`make check`) and fails loudly
if either binary comes out dynamically linked (checked via `file`, not `ldd` - musl's static-PIE
binaries carry a `PT_INTERP` pointing at `ld-musl-*.so.1` for self-relocation, which `ldd`
misreports as a real dynamic dependency even though the binary runs standalone; verified by
actually running the built `scratch` image's binaries).

## Versioning

Tags (`vX.Y.Z[+birdA.B.C]`) follow this repository's own cadence: bumping BIRD here implies
nothing about any consumer's version, and vice versa.

## License

BIRD itself is GPLv2-or-later (see `COPYING`, copied verbatim from the FSF). Distributing the
image distributes BIRD binaries, so §3's obligation to offer the corresponding source applies as
it does to any GPL binary; what building upstream verbatim removes is §2(a)'s duty to mark
changed files, because there are none. The exact source is `BIRD_REV` in the `Dockerfile`,
fetched from the upstream repository named there.

This repository's own additions - the `Dockerfile` and CI - are distributed under the same terms.
A program that talks to BIRD over its control socket or as a subprocess is not linked with it and
keeps its own licensing.
