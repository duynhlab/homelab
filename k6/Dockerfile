FROM grafana/k6:latest

WORKDIR /scripts

# Build argument for script name
ARG SCRIPT_NAME

# Copy the specific script based on build arg
COPY ${SCRIPT_NAME}.js .

# Set ENV from ARG
ENV SCRIPT_NAME=${SCRIPT_NAME}

# Run k6 with the specified script
CMD ["sh", "-c", "k6 run /scripts/${SCRIPT_NAME}.js"]

