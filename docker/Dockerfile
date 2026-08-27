FROM 3arthqu4ke/headlessmc:2.10.0

ARG MINECRAFT_VERSION=1.21.11

ENV WAYLAND_DISPLAY=headless
ENV ALSOFT_DRIVERS=null
ENV WYNNMARKET_OPENAL_LIBRARY=libopenal.so.1

RUN apt-get update \
	&& apt-get install --yes --no-install-recommends \
		libflite1 \
		libopenal1 \
	&& rm -rf /var/lib/apt/lists/*

COPY --chmod=644 docker/alsoft.conf /etc/openal/alsoft.conf

RUN hmc download "${MINECRAFT_VERSION}" \
	&& hmc fabric "${MINECRAFT_VERSION}" \
	&& hmc specifics 1 hmc-specifics

COPY --chmod=644 fabric/build/libs/wynnmarket-1.0.0.jar /headlessmc/HeadlessMC/run/mods/wynnmarket.jar
COPY --chmod=644 fabric/build/standaloneMods/ /headlessmc/HeadlessMC/run/mods/
COPY --chmod=644 docker/log4j2-wynnmarket.xml /headlessmc/log4j2-wynnmarket.xml
COPY --chmod=644 docker/headlessmc-config.properties /headlessmc/HeadlessMC/config.properties
COPY --chmod=755 docker/headlessmc-entrypoint.sh /usr/local/bin/wynnmarket-entrypoint
COPY --chmod=755 docker/healthcheck.sh /usr/local/bin/wynnmarket-healthcheck

WORKDIR /headlessmc

ENTRYPOINT ["/usr/local/bin/wynnmarket-entrypoint"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=10m --retries=2 CMD ["/usr/local/bin/wynnmarket-healthcheck"]
