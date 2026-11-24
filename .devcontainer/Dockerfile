FROM espressif/idf:v6.0

ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

RUN apt-get update -y && apt-get install udev tree vim-tiny jq -y

RUN echo "source /opt/esp/idf/export.sh > /dev/null 2>&1" >> ~/.bashrc
RUN echo "set -o vi" >> ~/.bashrc

RUN curl -L https://wokwi.com/ci/install.sh | sh
RUN bash -c "source /opt/esp/idf/export.sh && python -m pip install --upgrade pip && python -m pip install pytest idf-ci pytest-embedded-idf pytest-embedded-wokwi"


RUN apt-get update -y && apt-get install clang-tidy -y

ARG GITLEAKS_VERSION=8.30.1
ARG GH_VERSION=2.105.0
ARG GH_ACTIONS_LOCK_VERSION=0.5.1
ARG ESP_IDF_SBOM_VERSION=1.5.0

RUN curl -fsSL -o /tmp/gitleaks.tar.gz \
    "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
    && tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks \
    && rm /tmp/gitleaks.tar.gz \
    && gitleaks version

RUN curl -fsSL -o /tmp/gh.deb \
    "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.deb" \
    && apt-get install -y /tmp/gh.deb \
    && rm /tmp/gh.deb \
    && gh --version

RUN gh extension install github/gh-actions-lock --pin v${GH_ACTIONS_LOCK_VERSION} \
    && test -x "$HOME/.local/share/gh/extensions/gh-actions-lock/gh-actions-lock"

RUN bash -c "source /opt/esp/idf/export.sh && python -m pip install esp-idf-sbom==${ESP_IDF_SBOM_VERSION} && esp-idf-sbom --help > /dev/null"

ENTRYPOINT [ "/opt/esp/entrypoint.sh" ]

CMD ["/bin/bash", "-c"]