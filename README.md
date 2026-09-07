# bird

A fully statically-linked `bird`/`birdc` build, packaged as a minimal `scratch` container image
(`ghcr.io/slipmesh/bird`). It also carries `bird_exporter`, which reads the same control socket
and serves BIRD's protocol state to Prometheus.

Two upstreams, two licences, neither modified: BIRD is GPL, [`czerwonk/bird_exporter`] is MIT.
Both texts ship in the image under `/licenses/`, since a `scratch` image is the whole of what is
distributed and a notice left in this repository would reach nobody.
The exporter ships here rather than as an image of its own because it has to reach BIRD's control
socket, and that socket only exists beside the daemon.

[`czerwonk/bird_exporter`]: https://github.com/czerwonk/bird_exporter

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

Three binaries at `/`: `bird` (the daemon), `bird_exporter` (its Prometheus endpoint), and
`birdc` (the interactive control-socket client,
kept for manual `kubectl exec` debugging - `router` itself talks to the control socket directly,
not through `birdc`).

Built from `github.com/CZ-NIC/bird`, an official mirror of the real upstream
(`gitlab.nic.cz/labs/bird`) maintained by the same organization - verified byte-identical (same
commit per tag). Used instead of cloning gitlab.nic.cz directly because that 403s from GitHub
Actions' own IP range specifically, separately from
`bird.nic.cz`'s tarball downloads 403ing unconditionally for everyone. Pinned to a tag (see
`BIRD_REV` in the `Dockerfile`), currently `v3.3.2`.

The builder is an Ubuntu image rather than Alpine, because BIRD 3 does not survive a static musl
build - upstream's own `make check` dies in `filter_test` with SIGILL there, on both
architectures, while the same release passes all 31 tests against glibc. The `Dockerfile` carries
the full isolation and what it rules out.

`--disable-libssh` at configure time: BIRD's only use for libssh is RPKI-over-SSH transport, which
this project's BIRD config never uses. `libncurses-dev`/`libreadline-dev` provide the `.a`
archives `birdc`'s interactive line editing links against instead of pulling in
`libncursesw.so`/`libreadline.so`. The build also runs BIRD's own unit test suite (`make check`)
and fails loudly if either binary comes out dynamically linked, checked via `file` rather than
`ldd`, whose wording varies by libc; both binaries were verified by running them in an empty
chroot holding nothing else.

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
