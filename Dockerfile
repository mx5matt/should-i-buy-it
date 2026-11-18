FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TZ=Pacific/Auckland

WORKDIR /app

RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid 10001 --create-home app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py CHANGELOG.md ./
COPY templates ./templates
COPY static ./static
COPY tests ./tests

RUN mkdir -p /data && chown -R app:app /app /data

USER 10001:10001
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=3)"

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--threads", "4", "--access-logfile", "-", "app:app"]
