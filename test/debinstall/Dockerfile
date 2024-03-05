FROM ubuntu:20.04

# Keep this as barebones as possible. The aim is to test the installation of
# the packages on a clean system.

## This might be necessary at some point.
# RUN apt-get update && \
#     env DEBIAN_FRONTEND=noninteractive apt-get install -qy \
#     debhelper

COPY test/debinstall/debinstall.sh test/debinstall/smoketest.sh /
ENTRYPOINT ["/debinstall.sh"]
