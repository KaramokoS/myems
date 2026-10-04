FROM python:3.10-slim

RUN mkdir -p /var/www/myems-admin/upload

WORKDIR /app

# Copy requirements first to leverage Docker layer caching
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source
COPY . /app

EXPOSE 8000
CMD ["gunicorn", "app:api", "-b", "0.0.0.0:8000", "--timeout", "600", "--workers=4"]