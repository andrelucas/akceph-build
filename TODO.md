# TODO for akceph-build

## Packaging

- (HIGH) lock down specific Ubuntu version (i.e. a specific container hash, as
  listed [here](https://hub.docker.com/_/ubuntu/tags?page=1&name=focal))

## Build speed

- (MED) Patch in use of ld.gold(1) for dpkg builds. There's no good reason to
  use an old slow linker that doesn't properly link in tcmalloc
- (MED) Disable DWZ on v18 builds

## Optimisation

- (MED) ensure packaged versions target more specific amd64 platform
