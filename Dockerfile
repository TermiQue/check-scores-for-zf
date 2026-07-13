FROM python:3.12-slim@sha256:423ed6ab25b1921a477529254bfeeabf5855151dc2c3141699a1bfc852199fbf

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt requirements.lock ./
RUN pip install --no-cache-dir -r requirements.lock

COPY scripts ./scripts
COPY zfcheck ./zfcheck

RUN mkdir -p /data && chown -R 10001:10001 /app /data
USER 10001:10001

VOLUME ["/data"]
ENTRYPOINT ["python", "-m", "zfcheck"]
CMD ["run"]
