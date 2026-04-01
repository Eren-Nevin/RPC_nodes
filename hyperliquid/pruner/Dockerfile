FROM debian:12.6-slim

ARG USERNAME=hluser
ARG USER_UID=10000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update -y && apt-get install curl cron procps -y \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /home/$USERNAME/hl/data && mkdir -p /home/$USERNAME/scripts && chown -R $USERNAME:$USERNAME /home/$USERNAME/hl

COPY scripts/ /home/$USERNAME/scripts/
COPY cron/ /etc/

RUN chmod 0644 /etc/cron.d/* && \
    chmod +x /home/$USERNAME/scripts/* && chown -R $USERNAME:$USERNAME /home/$USERNAME/scripts

CMD ["bash", "-c", "crontab /etc/cron.d/prune && /usr/sbin/cron -f -L 15"]
