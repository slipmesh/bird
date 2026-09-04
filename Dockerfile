# Builds a fully statically-linked `bird`/`birdc` (no libc/ncurses/readline/libssh runtime
# dependencies) from BIRD's own upstream source, and packages just those two binaries into a
# `scratch` image - meant to run as a sidecar next to whatever renders BIRD's config, sharing a
# volume for the config file and the control socket.
#
# Source is cloned from github.com/CZ-NIC/bird - an official mirror maintained by the same
# organization as the real upstream (gitlab.nic.cz/labs/bird), verified byte-identical (same
# commit hash for v2.19.2 on both). Cloning gitlab.nic.cz directly instead 403s specifically from
# GitHub Actions' own IP range - bird.nic.cz's tarball downloads 403 unconditionally, and
# gitlab.nic.cz apparently blocks
# at least some cloud/CI IP ranges. github.com obviously isn't blocked from GitHub's own runners.
#
# BIRD_REV is a tag, verified to actually exist on gitlab.nic.cz before being pinned here (not
# guessed). v2.19.2 is the latest 2.x release and the version verified against the RFC 8950
# (extended next-hop) underlay redesign on a real testbed.
#
# --disable-libssh: only used by BIRD's optional RPKI-over-SSH transport, which this project
# doesn't use (no RPKI protocol anywhere in slipmesh's BIRD config) - dropping it removes libssh
# from the dependency list entirely rather than needing to statically link it too.
# --enable-client stays at its default (yes): birdc is kept for manual debugging, even though a
# consumer that speaks the control socket directly has no use for it. ncurses-static/
# readline-static provide the .a archives birdc's build links against instead of the normal
# shared libncursesw.so/libreadline.so.
#
# Staying on the 2.x line for now. v3.3.2 configures, compiles and links statically here without
# complaint, but upstream's own `make check` then dies in filter_test with SIGILL (make reports
# Error 132) while tree_test and trie_test from the same directory pass. Undiagnosed - moving to
# 3.x is a task of its own, with room to diagnose that, not a line to flip in passing.
#
# BIRD is built from vanilla upstream, unmodified. Keep it that way: a local patch makes this a
# modified GPL work, with the disclosure that carries.
FROM alpine:3.24 AS builder
ARG BIRD_REV=v2.19.2
RUN apk add --no-cache \
        build-base musl-dev linux-headers \
        git m4 perl autoconf flex bison \
        ncurses-static readline-static \
    && git clone https://github.com/CZ-NIC/bird.git /src \
    && git -C /src checkout "$BIRD_REV" \
    && cd /src \
    && autoreconf \
    && ./configure --disable-libssh \
    && make LDFLAGS=-static -j"$(nproc)" \
    # BIRD's own unit test suite (lib/nest/filter data-structure and parser tests) - fails the
    # build loudly if this specific static-musl toolchain miscompiles something the upstream test
    # suite would catch, not just "it links".
    && make LDFLAGS=-static -j"$(nproc)" check \
    && strip bird birdc \
    # Static-link sanity check - fails the build loudly instead of silently shipping a
    # dynamically-linked binary that happens to still run in this builder stage's own userland.
    # `file`, not `ldd`: musl's static-PIE binaries still carry a PT_INTERP pointing at
    # ld-musl-*.so.1 (self-relocation, not a real runtime dependency on an external .so), which
    # makes `ldd` misreport them as dynamically linked even though they run standalone with zero
    # files beyond themselves - verified empirically by running the built binary in a `scratch`
    # image with nothing else in it.
    && file bird | grep -q 'static' \
    && file birdc | grep -q 'static'

FROM scratch
COPY --from=builder /src/bird /src/birdc /
ENTRYPOINT ["/bird"]
