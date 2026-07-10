ARG RUBY_VERSION=4.0.5
FROM ruby:${RUBY_VERSION}-slim

# Debian slim's packaged dash is older than rush's current differential oracle.
# Build the upstream release explicitly so container and native corpus results agree.
ARG DASH_VERSION=0.5.13.4
ARG DASH_SHA256=d10dfd41cda59165560db39ca915c2c4a7636fff04281d8d2df77ad92c753e2b

ENV BUNDLE_PATH=/bundle \
    BUNDLE_BIN=/bundle/bin \
    GEM_HOME=/bundle \
    DEBIAN_FRONTEND=noninteractive

# procps supplies ps for the job-control pty smoke's pgid/tpgid probes.
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates curl git procps \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /bundle /work /tmp/rush-home \
    && chmod 0777 /bundle /work /tmp/rush-home

RUN curl -fsSL "http://gondor.apana.org.au/~herbert/dash/files/dash-${DASH_VERSION}.tar.gz" \
      -o /tmp/dash.tar.gz \
    && echo "${DASH_SHA256}  /tmp/dash.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/dash.tar.gz -C /tmp \
    && cd "/tmp/dash-${DASH_VERSION}" \
    && ./configure --bindir=/usr/bin --mandir=/usr/share/man \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/dash.tar.gz "/tmp/dash-${DASH_VERSION}"

WORKDIR /work
