FROM grafana/k6:latest

WORKDIR /scripts

# Build argument for script name
ARG SCRIPT_NAME

# Copy the specific script based on build arg
COPY ${SCRIPT_NAME}.js script.js

# Set ENV from ARG (for reference)
ENV SCRIPT_NAME=${SCRIPT_NAME}

# Run k6 directly with the script (no shell needed - distroless image)
# Script is always copied as script.js regardless of SCRIPT_NAME
CMD ["k6", "run", "/scripts/script.js"]

