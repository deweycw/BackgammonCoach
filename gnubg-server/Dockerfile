FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    gnubg python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/games/gnubg /usr/local/bin/gnubg

WORKDIR /app
RUN python3 -m venv /app/venv
ENV PATH="/app/venv/bin:$PATH"

COPY pyproject.toml .
RUN pip install --no-cache-dir .
COPY app/ app/

EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
