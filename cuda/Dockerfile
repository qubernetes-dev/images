# from https://dev.to/yuesu/setting-up-vgpu-in-docker-container-with-specific-python-version-5ei6

ARG PYTHON_VERSION="3.12"

# Use an official NVIDIA CUDA runtime as a parent image
FROM nvidia/cuda:12.8.1-base-ubuntu24.04
ARG PYTHON_VERSION


# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Helsinki

# Install Deadsnakes PPA
RUN apt-get update
RUN apt install software-properties-common -y
RUN add-apt-repository ppa:deadsnakes/ppa
RUN apt-get update

RUN echo "Using Python version: ${PYTHON_VERSION}" 

# Install Python and pip
RUN apt-get install -y \
  python${PYTHON_VERSION} \
  python${PYTHON_VERSION}-venv
# Clean apt cache to reduce image size
RUN  apt-get purge -y software-properties-common && \
  apt-get autoremove -y && \
  rm -rf /var/lib/apt/lists/*

# Create a venv for Python 3.12 and upgrade pip in there
RUN python${PYTHON_VERSION} -m venv /opt/py${PYTHON_VERSION}
RUN /opt/py${PYTHON_VERSION}/bin/pip install --upgrade pip setuptools wheel

# Create symbolic links for Python in virtual environment
RUN ln -sf /opt/py${PYTHON_VERSION}/bin/python /usr/local/bin/python
RUN ln -sf /opt/py${PYTHON_VERSION}/bin/pip /usr/local/bin/pip

RUN python --version
RUN which python
RUN pip --version
RUN which pip

COPY requirements-cu12.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

