FROM ubuntu:20.04

RUN mkdir /release
COPY release/ /release
COPY debinstall.sh /
RUN /debinstall.sh
RUN rm /debinstall.sh

ENTRYPOINT ["/bin/bash"]
