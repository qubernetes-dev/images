# Use an official Python runtime as a parent image
FROM python:3.9-slim

# Set the working directory
WORKDIR /app

# Copy the requirements file into the container
COPY requirements.txt .

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Make port 5000 available to the world outside this container
EXPOSE 5000

# Note: The command to run mlflow server is specified in the Kubernetes deployment (mlflow.yaml)
# No CMD or ENTRYPOINT needed here if the k8s manifest overrides it.