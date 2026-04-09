ARG ROCM_BUILD_IMAGE=rocm/dev-ubuntu-22.04:6.2.4-complete
ARG ROCM_RUNTIME_IMAGE=rocm/dev-ubuntu-22.04:6.2.4

FROM ${ROCM_BUILD_IMAGE} AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG QISKIT_VERSION=2.3.1
ARG QISKIT_AER_REF=0.17.2
ARG AER_MPI=OFF
ARG AER_ROCM_ARCH=gfx90a

ENV ROCM_PATH=/opt/rocm
ENV QISKIT_ADD_CUDA_REQUIREMENTS=False
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

SHELL ["/bin/bash", "-lc"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    build-essential \
    cmake \
    ninja-build \
    pkg-config \
    gfortran \
    mpich \
    libmpich-dev \
    libopenblas-dev \
    liblapack-dev \
    libblas-dev \
    libssl-dev \
    libffi-dev \
    libsuitesparse-dev \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    python3-yaml \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN python3 -m venv /opt/venv
ENV PATH=/opt/venv/bin:${PATH}

RUN python -m pip install --upgrade pip setuptools wheel build && \
    python -m pip install \
      pybind11 \
      scikit-build \
      "conan<2.0.0" \
      numpy

RUN conan config init && \
    python - <<'PY'
from pathlib import Path
import yaml

p = Path("/root/.conan/settings.yml")
data = yaml.safe_load(p.read_text())

clang_versions = [str(v) for v in data["compiler"]["clang"]["version"]]
if "18" not in clang_versions:
    clang_versions.append("18")
data["compiler"]["clang"]["version"] = clang_versions

p.write_text(yaml.safe_dump(data, sort_keys=False))
print("Patched Conan settings.yml to allow clang 18")
PY

RUN git clone --branch "${QISKIT_AER_REF}" --depth 1 https://github.com/Qiskit/qiskit-aer.git
WORKDIR /build/qiskit-aer

RUN python -m pip install -r requirements-dev.txt

RUN export LD_LIBRARY_PATH="${ROCM_PATH}/lib:${ROCM_PATH}/lib64:${LD_LIBRARY_PATH}" && \
    QISKIT_AER_PACKAGE_NAME='qiskit-aer-gpu-rocm' \
    python setup.py bdist_wheel -- \
      -DAER_THRUST_BACKEND=ROCM \
      -DAER_MPI=${AER_MPI} \
      -DAER_ROCM_ARCH=${AER_ROCM_ARCH}

FROM ${ROCM_RUNTIME_IMAGE} AS runtime

ARG DEBIAN_FRONTEND=noninteractive
ARG QISKIT_VERSION=2.3.1

ENV ROCM_PATH=/opt/rocm
ENV QISKIT_ADD_CUDA_REQUIREMENTS=False
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PATH=/opt/venv/bin:${PATH}

SHELL ["/bin/bash", "-lc"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    python3 \
    python3-pip \
    python3-venv \
    libopenblas-dev \
    liblapack-dev \
    libblas-dev \
    libsuitesparse-dev \
    graphviz \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv && \
    python -m pip install --upgrade pip setuptools wheel

COPY --from=builder /build/qiskit-aer/dist/qiskit_aer_gpu_rocm-*.whl /tmp/

RUN python -m pip install \
      "qiskit==${QISKIT_VERSION}" \
      /tmp/qiskit_aer_gpu_rocm-*.whl \
      pylatexenc \
      numpy \
      scipy \
      sympy \
      networkx \
      rustworkx \
      && rm -f /tmp/qiskit_aer_gpu_rocm-*.whl

WORKDIR /workspace
CMD ["/bin/bash"]