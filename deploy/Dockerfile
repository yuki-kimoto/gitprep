FROM alpine:3.9 as BUILDER

# Update OS and install dependencies
RUN set -x \
    && apk update \
    && apk upgrade \
    && apk --no-cache add \
        tini \
        bash \
        shadow \
        perl \
        perl-dev \
        gcc \
        g++ \
        curl \
        wget \
        make

# Install GitPrep
RUN set -x \
    && mkdir -m 700 /home/gitprep \
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

FROM alpine:3.9

RUN set -x \
    && apk update \
    && apk upgrade \
    && apk --no-cache add \
        tini \
        bash \
        shadow \
        perl \
        git \
        openssh-server

# Create user gitprep
RUN set -x \
    && useradd -m gitprep \
    && mkdir -p -m 700 /home/gitprep/.ssh \
    && usermod -p '*' gitprep \
    && touch /home/gitprep/.ssh/authorized_keys \
    && chmod 600 /home/gitprep/.ssh/authorized_keys \
    && chown -R gitprep:gitprep /home/gitprep/.ssh \
    && sed -i 's/#PasswordAuthentication yes.*/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#ChallengeResponseAuthentication yes.*/ChallengeResponseAuthentication no /' /etc/ssh/sshd_config

COPY --chown=gitprep:gitprep --from=BUILDER /home/gitprep/gitprep /home/gitprep/gitprep

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
