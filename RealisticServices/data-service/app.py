import os
import time

from fastapi import FastAPI, HTTPException, Request, Response
from pydantic import BaseModel, EmailStr
import psycopg2
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from psycopg2.extras import RealDictCursor

app = FastAPI(title="data-service", version="1.0.0")

DB_HOST = os.getenv("DB_HOST", "postgres")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "mubench")
DB_USER = os.getenv("DB_USER", "mubench")
DB_PASSWORD = os.getenv("DB_PASSWORD", "mubench")

HTTP_REQUESTS_TOTAL = Counter(
    "mubench_http_requests_total",
    "Total HTTP requests",
    ["service", "method", "path", "status"],
)
HTTP_REQUEST_DURATION_SECONDS = Histogram(
    "mubench_http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["service", "method", "path"],
)
DB_QUERY_DURATION_SECONDS = Histogram(
    "mubench_db_query_duration_seconds",
    "Database query latency in seconds",
    ["service", "query_name"],
)


class CreateUserRequest(BaseModel):
    username: str
    email: EmailStr


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    service = "data-service"
    method = request.method
    path = request.url.path

    started = time.time()
    status = "500"
    try:
        response = await call_next(request)
        status = str(response.status_code)
        return response
    finally:
        elapsed = time.time() - started
        HTTP_REQUESTS_TOTAL.labels(service=service, method=method, path=path, status=status).inc()
        HTTP_REQUEST_DURATION_SECONDS.labels(service=service, method=method, path=path).observe(elapsed)


def get_conn():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=3,
    )


@app.get("/health")
def health() -> dict:
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
    except Exception as exc:
        return {"status": "degraded", "service": "data-service", "error": str(exc)}
    return {"status": "ok", "service": "data-service"}


@app.get("/metrics")
def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/users/{user_id}")
def get_user(user_id: int) -> dict:
    started = time.time()
    db_started = time.time()
    try:
        with get_conn() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "SELECT id, username, email, created_at FROM app_users WHERE id = %s",
                    (user_id,),
                )
                row = cur.fetchone()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"database error: {exc}")
    finally:
        DB_QUERY_DURATION_SECONDS.labels(service="data-service", query_name="get_user_by_id").observe(
            time.time() - db_started
        )

    if not row:
        raise HTTPException(status_code=404, detail="user not found")

    return {
        "data": row,
        "db_latency_ms": round((time.time() - started) * 1000.0, 3),
    }


@app.get("/users")
def list_users(limit: int = 50, offset: int = 0) -> dict:
    started = time.time()
    db_started = time.time()
    safe_limit = max(1, min(limit, 500))
    safe_offset = max(0, offset)

    try:
        with get_conn() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "SELECT id, username, email, created_at FROM app_users ORDER BY id LIMIT %s OFFSET %s",
                    (safe_limit, safe_offset),
                )
                rows = cur.fetchall()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"database error: {exc}")
    finally:
        DB_QUERY_DURATION_SECONDS.labels(service="data-service", query_name="list_users").observe(
            time.time() - db_started
        )

    return {
        "data": rows,
        "count": len(rows),
        "limit": safe_limit,
        "offset": safe_offset,
        "db_latency_ms": round((time.time() - started) * 1000.0, 3),
    }


@app.post("/users")
def create_user(payload: CreateUserRequest) -> dict:
    started = time.time()
    db_started = time.time()

    try:
        with get_conn() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "INSERT INTO app_users (username, email) VALUES (%s, %s) RETURNING id, username, email, created_at",
                    (payload.username, payload.email),
                )
                row = cur.fetchone()
            conn.commit()
    except psycopg2.errors.UniqueViolation:
        raise HTTPException(status_code=409, detail="username or email already exists")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"database error: {exc}")
    finally:
        DB_QUERY_DURATION_SECONDS.labels(service="data-service", query_name="create_user").observe(
            time.time() - db_started
        )

    return {
        "data": row,
        "db_latency_ms": round((time.time() - started) * 1000.0, 3),
    }
