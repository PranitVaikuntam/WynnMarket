FROM 3arthqu4ke/headlessmc:2.9.0

ARG MINECRAFT_VERSION=1.21.11

ENV WAYLAND_DISPLAY=headless

RUN hmc download "${MINECRAFT_VERSION}" \
	&& hmc fabric "${MINECRAFT_VERSION}" \
	&& hmc specifics 1 hmc-specifics

COPY --chmod=644 fabric/build/libs/wynnmarket-1.0.0.jar /headlessmc/HeadlessMC/run/mods/wynnmarket.jar
COPY --chmod=644 fabric/build/standaloneMods/ /headlessmc/HeadlessMC/run/mods/
COPY --chmod=755 docker/headlessmc-entrypoint.sh /usr/local/bin/wynnmarket-entrypoint

WORKDIR /headlessmc

ENTRYPOINT ["/usr/local/bin/wynnmarket-entrypoint"]
CMD ["bash", "-lc", "sleep infinity"]
