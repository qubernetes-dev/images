ARG ROCM_RUNTIME_IMAGE=rocm/dev-ubuntu-22.04:6.2.4

FROM ${ROCM_RUNTIME_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive

ENV ROCM_PATH=/opt/rocm
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PATH=/opt/venv/bin:${ROCM_PATH}/bin:${PATH}
ENV LD_LIBRARY_PATH=${ROCM_PATH}/lib:${ROCM_PATH}/lib64:${LD_LIBRARY_PATH}

SHELL ["/bin/bash", "-lc"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv && \
    python -m pip install --upgrade pip setuptools wheel

WORKDIR /workspace

CMD ["/bin/bash"]