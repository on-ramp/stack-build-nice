# `stack-build-nice` #

This is an unprivileged (rootless) Docker Image for building Haskell using Stack.

GHC version: 8.6.5

Cabal version: 2.4.1.0

Stack version: 2.3.3

The image is `FROM alpine` but configured for building static binaries; build outputs will run on any other Linux distro. Musl libc is linked into those binaries.
