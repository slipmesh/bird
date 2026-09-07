# Builds a fully statically-linked `bird`/`birdc` (no libc/ncurses/readline/libssh runtime
# dependencies) from BIRD's own upstream source, and packages just those two binaries into a
# `scratch` image - meant to run as a sidecar next to whatever renders BIRD's config, sharing a
# volume for the config file and the control socket.
#
# Source is cloned from github.com/CZ-NIC/bird - an official mirror maintained by the same
# organization as the real upstream (gitlab.nic.cz/labs/bird), verified byte-identical (same
# commit hash for v3.3.2 on both). Cloning gitlab.nic.cz directly instead 403s specifically from
# GitHub Actions' own IP range - bird.nic.cz's tarball downloads 403 unconditionally, and
# gitlab.nic.cz apparently blocks
# at least some cloud/CI IP ranges. github.com obviously isn't blocked from GitHub's own runners.
#
# BIRD_REV is a tag, verified to actually exist on gitlab.nic.cz before being pinned here (not
# guessed). A tag rather than a commit is load-bearing: the clone below is shallow, and --branch
# resolves tags and branches only.
#
# --disable-libssh: only used by BIRD's optional RPKI-over-SSH transport, which this project
# doesn't use (no RPKI protocol anywhere in slipmesh's BIRD config) - dropping it removes libssh
# from the dependency list entirely rather than needing to statically link it too.
# --enable-client stays at its default (yes): birdc is kept for manual debugging, even though a
# consumer that speaks the control socket directly has no use for it. libncurses-dev and
# libreadline-dev carry the .a archives birdc's build links against instead of the normal
# shared libncursesw.so/libreadline.so.
#
# Built against glibc rather than musl, which is why the builder is not Alpine. BIRD 3 does not
# survive a static musl build: upstream's own `make check` dies in filter_test with SIGILL, on
# amd64 and arm64 alike and natively on each. Isolated by varying one thing at a time - the same
# v3.3.2 passes all 31 tests against glibc, dynamically and statically linked both, while a musl
# build of the same tree crashes in lib/hash_test's t_spinhash_basic, ten runs out of ten. The
# crash lands in BIRD's own page allocator, reached from rcu_read_lock() through
# page_fill_hot(), which is the path 3.3.2 introduced ("Allocator: Pre-fill hot pages when
# entering RCU critical section" in its NEWS), and the faulting thread moves between runs -
# memory corruption rather than a failed assertion. Ruled out on the way: the release itself,
# static linking, the architecture, QEMU (both CI legs run native), musl's default thread stack
# size (BIRD gives its own threads 64K explicitly), and a late-initialized page_size.
#
# glibc asks one thing in return: NSS. getaddrinfo, getpwnam and getgrnam resolve through
# backends glibc used to dlopen, which a static binary cannot carry - hence the linker warnings
# this build prints. Since glibc 2.34 the files and dns backends live inside libc itself, so a
# static binary resolves names given nothing but /etc/resolv.conf, verified in an empty chroot
# on glibc 2.43. None of those calls is reachable here regardless: getaddrinfo serves
# `log ... udp <hostname>` and the RPKI protocol, getpwnam/getgrnam serve -u/-g, and this
# project logs to stderr, configures no RPKI, and starts bird as `bird -f -c <conf> -s <sock>`.
#
# Protocols stay at configure's default of all. Trimming them to the four slipmesh uses breaks
# upstream's suite - filter/test.conf reads babel_metric, so filter_test aborts outright when
# babel is left out - and the `make check` below is worth more than the 0.7 MB it would save.
#
# BIRD is built from vanilla upstream, unmodified. Keep it that way: a local patch makes this a
# modified GPL work, with the disclosure that carries.
#
# The image also carries czerwonk/bird_exporter (MIT), which reads BIRD's own control socket and
# serves its protocol state to Prometheus. It ships here rather than as an image of its own
# because it has to reach that socket, and the socket only exists next to the daemon: whatever
# runs it is already in this filesystem. Two upstreams, two licences - BIRD stays GPL, the
# exporter is MIT, and neither is modified.
FROM ubuntu:26.04 AS builder
ARG BIRD_REV=v3.3.2
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates file git m4 perl autoconf flex bison \
        libncurses-dev libreadline-dev \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --depth 1 --branch "$BIRD_REV" https://github.com/CZ-NIC/bird.git /src \
    && cd /src \
    && autoreconf \
    && ./configure --disable-libssh \
    && make LDFLAGS=-static -j"$(nproc)" \
    # BIRD's own unit test suite (lib/nest/filter data-structure and parser tests) - fails the
    # build loudly if this specific static-glibc toolchain miscompiles something the upstream
    # test suite would catch, not just "it links". It is also what caught musl: see above.
    && make LDFLAGS=-static -j"$(nproc)" check \
    && strip bird birdc \
    # Static-link sanity check - fails the build loudly instead of silently shipping a
    # dynamically-linked binary that happens to still run in this builder stage's own userland.
    # `file` reads the ELF itself and says `statically linked` outright, where `ldd` answers in
    # wording that varies by libc. Verified by running both binaries in an empty chroot holding
    # nothing but them.
    && file bird | grep -q 'static' \
    && file birdc | grep -q 'static'

# CGO off is what makes the result runnable in `scratch`: with it on, net and os/user link
# against the builder's glibc and the binary needs files this image does not have.
FROM golang:1.27.1-trixie AS exporter
ARG BIRD_EXPORTER_REV=v1.6.2
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends file \
    && rm -rf /var/lib/apt/lists/* \
    && CGO_ENABLED=0 go install github.com/czerwonk/bird_exporter@${BIRD_EXPORTER_REV} \
    && mv "$(go env GOPATH)/bin/bird_exporter" /bird_exporter \
    && file /bird_exporter | grep -q 'statically linked'

FROM scratch
COPY --from=builder /src/bird /src/birdc /
COPY --from=exporter /bird_exporter /
ENTRYPOINT ["/bird"]
