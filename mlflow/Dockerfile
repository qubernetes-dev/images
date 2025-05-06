# Use an official Python runtime as a parent image
FROM python:3.9-slim

# Set the working directory
WORKDIR /app

# Copy the requirements file into the container
COPY requirements.txt .

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy the entrypoint script into the working directory and make it executable
COPY entrypoint.sh .
RUN chmod +x ./entrypoint.sh

# Make port 5000 available to the world outside this container
EXPOSE 5000

# Set the entrypoint script to run when the container starts
ENTRYPOINT ["./entrypoint.sh"]

# Optional: Define default command arguments if the entrypoint expects them via "$@"
# CMD ["--workers", "4"]