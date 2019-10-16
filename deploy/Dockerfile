FROM alpine:3.9

# Update OS and install dependencies
RUN set -x \
    && apk update \
    && apk upgrade \
    && apk --no-cache add \
        tini \
        bash \
        shadow \
        perl \
        git \
        openssh-server \
        perl-dev \
        gcc \
        g++ \
        curl \
        wget \
        make

# Create user gitprep
RUN set -x \
    && useradd -m gitprep \
    && mkdir -m 700 /home/gitprep/.ssh \
    && usermod -p '*' gitprep \
    && touch /home/gitprep/.ssh/authorized_keys \
    && chmod 600 /home/gitprep/.ssh/authorized_keys \
    && chown -R gitprep:gitprep /home/gitprep/.ssh \
    && sed -i 's/#PasswordAuthentication yes.*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#ChallengeResponseAuthentication yes.*/ChallengeResponseAuthentication no /' /etc/ssh/sshd_config

USER gitprep

# Install GitPrep
RUN set -x \
    && git --version \
    && perl -v \
    && curl -kL https://github.com/yuki-kimoto/gitprep/archive/latest.tar.gz \
        > /home/gitprep/gitprep-latest.tar.gz \
    && mkdir /home/gitprep/gitprep \
    && tar -zxf /home/gitprep/gitprep-latest.tar.gz \
        --strip-components=1 -C /home/gitprep/gitprep \
    && rm -f /home/gitprep/gitprep-latest.tar.gz \
    && cd /home/gitprep/gitprep \
    && PERL_USE_UNSAFE_INC=1 ./setup_module \
    && prove t \
    && ./setup_database

USER root

# Clean obsolete Packages
RUN set -x \
    && apk del --no-cache \
        perl-dev \
        gcc \
        g++ \
        curl \
        wget \
        make

# Copy start script
COPY ./docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 700 /docker-entrypoint.sh

# Expose default HTTP connector port.
EXPOSE 10020
EXPOSE 22

# Set volume mount point
VOLUME ["/home/gitprep"]

# Set the default working directory as the installation directory.
WORKDIR /home/gitprep

# Set entrypoint to invoke tini as PID1
ENTRYPOINT ["/sbin/tini","--","/docker-entrypoint.sh"]
