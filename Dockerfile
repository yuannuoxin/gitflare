FROM node:20-slim

RUN apt-get update && \
    apt-get install -y git && \
#    apt-get install -y bsdmainutils && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g wrangler

WORKDIR /app
COPY entrypoint.sh start.sh ./
RUN chmod +x entrypoint.sh start.sh

ENV GIT_REPO=""
ENV WORKER_SCRIPT="_worker.js"
ENV PORT=8080
ENV HOST=0.0.0.0
ENV PERSIST=false
ENV PERSIST_PATH=/app/data

ENTRYPOINT ["/app/entrypoint.sh"]