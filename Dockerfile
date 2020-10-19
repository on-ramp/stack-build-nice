#-- Haskell Stack non-privileged builder image.
#--
#-- Installs Stack from official signed binary,
#--   then GHC from musl bindist (via stack setup).
#--
#-- Usage:
#--   docker build -t coinweb/stack-build-nice:latest .

FROM alpine:3.12

LABEL vendor="Coinweb Ltd."

RUN apk update --no-cache && \
    apk add --no-cache \
        curl \
        gcc \
        gnupg \
        gmp-dev \
        libc-dev \
        make \
        ncurses-libs \
        perl \
        sudo \
        zlib-dev \
    ; # [+189MiB]

# Alpine has libtinfo linked into libncurses
RUN ln -vsf libncursesw.so.6 /usr/lib/libtinfow.so.6

ARG GHC_VERSION=8.6.5
ARG STACK_RESOLVER=lts-14.27

ENV STACK_BIN=https://github.com/commercialhaskell/stack/releases/download/v2.5.1/stack-2.5.1-linux-x86_64-bin
# Not using a STACK_VERSION variable, because they subtly changed
# the asset naming/url scheme between v2.3.1 and v2.3.3. Use sed and caution
WORKDIR /usr/local/share
COPY stack-2.5.1-linux-x86_64-bin.sha256 \
     stack-2.5.1-linux-x86_64-bin.asc \
     GPG-KEY-575159689BEFB442-dev@fpcomplete \
     ./
# hadolint ignore=DL4006
RUN curl -fsSL "$STACK_BIN" -o ${STACK_BIN##*/} && \
    sha256sum -c stack-*-linux-x86_64-bin.sha256 >&2 && \
    gpg -q --import GPG-KEY-* && \
    printf "trust\n5\ny\n" | gpg --command-fd 0 --no-tty --edit-key 575159689BEFB442 2>/dev/null && \
    gpg --verify stack-*-linux-x86_64-bin.asc && \
    rm -rf ~/.gnupg && \
    mv -v stack-*-linux-x86_64-bin /usr/local/bin/stack && \
    chmod 755 /usr/local/bin/stack && \
    echo "stack binary verified and installed." >&2 && \
    stack --version
    # [+60 MiB]

#-- drop root
# hadolint ignore=SC2016
RUN adduser -D -u 1000 builder && \
    echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/enable-builder-sudo && \
    sed -i 's:profile\.d/\*\.sh:profile.d/*:' /etc/profile && \
    printf 'test -d "$HOME/bin" && [ "${PATH#*$HOME/bin}" == "$PATH" ] && export PATH="$PATH:$HOME/bin"' > /etc/profile.d/add-home-bin-to-PATH && \
    printf 'export PATH="$PATH:$(stack path --compiler-bin)"' > /etc/profile.d/add-stack-ghc-to-PATH && \
    :
# workaround sudo bug 42 https://github.com/sudo-project/sudo/issues/42
RUN echo 'Set disable_coredump false' >> /etc/sudo.conf
USER builder
WORKDIR /home/builder
ENV ENV=/etc/profile

#-- configure Stack, pull a GHC, strip it down [+1.34 GiB]
COPY stack-config.yaml /tmp/
RUN install -Dm644 /tmp/stack-config.yaml /home/builder/.stack/config.yaml && \
    if [ "$GHC_VERSION" = "8.6.5" ]; then \
        sed -i 's!\(- --enable-executable-static\)!#\1 # requires Cabal 3.0+!' /tmp/stack-config.yaml; \
    fi && \
    stack setup \
        --install-ghc \
        --resolver=$STACK_RESOLVER \
        --ghc-variant=musl \
        $GHC_VERSION \
        ; success=$?; \
    rm -rf ~/.stack/programs/*/ghc-*.tar.xz \
           ~/.stack/programs/*/ghc-*/share/doc \
        ; \
    strip ~/.stack/programs/*/ghc-*/lib/ghc-*/bin/* 2>/dev/null \
        ; \
    exit $success

#-- almost done; pre-download snapshot index for speed [+1.29 GiB]
RUN stack update

#-- add correctly permissioned volumes for host code & build outputs
RUN mkdir src bin
VOLUME /home/builder/src
VOLUME /home/builder/bin
WORKDIR /home/builder/src
