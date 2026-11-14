FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8000
# newrelic-admin wraps the process: the agent reads NEW_RELIC_* env (license key, app name, AI monitoring flags) from k8s.yaml.
CMD ["newrelic-admin", "run-program", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
