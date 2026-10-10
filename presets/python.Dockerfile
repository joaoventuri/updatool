# syntax=docker/dockerfile:1
# updatool preset — Python (pip). With uv: --mount=type=cache,target=/root/.cache/uv uv sync --frozen
FROM python:3.12-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8000
COPY requirements.txt ./
RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["sh", "-c", "gunicorn -b 0.0.0.0:${PORT} app:app"]
