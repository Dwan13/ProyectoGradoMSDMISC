import os
import time
from collections import deque
from threading import Lock

from fastapi import FastAPI, Header, HTTPException, Request, Response
from pydantic import BaseModel, EmailStr
import jwt
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
import requests

app = FastAPI(title="api-service", version="1.0.0")

JWT_SECRET = os.getenv("JWT_SECRET", "mubench-dev-secret")
DATA_SERVICE_URL = os.getenv("DATA_SERVICE_URL", "http://data-service:8080")
RATE_LIMIT_ENABLED = False
RATE_LIMIT_RPM = 600

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
DOWNSTREAM_REQUEST_DURATION_SECONDS = Histogram(
    "mubench_downstream_request_duration_seconds",
    "Downstream request latency in seconds",
    ["service", "downstream", "method", "path"],
)


class CreateUserRequest(BaseModel):
    username: str
    email: EmailStr


_rate_lock = Lock()
_rate_window = deque()


def enforce_rate_limit() -> None:
    # Rate limiting desactivado, ahora se maneja en el gateway NGINX
    return


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    service = "api-service"
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


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "api-service"}


@app.get("/metrics")
def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


def decode_token(authorization: str | None) -> dict:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")

    token = authorization.split(" ", 1)[1]
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=401, detail=f"invalid token: {exc}")


@app.get("/profile")
def profile(user_id: int = 1, authorization: str | None = Header(default=None)) -> dict:
    enforce_rate_limit()
    claims = decode_token(authorization)

    started = time.time()
    try:
        resp = requests.get(f"{DATA_SERVICE_URL}/users/{user_id}", timeout=3)
    except requests.RequestException as exc:
        raise HTTPException(status_code=503, detail=f"data-service unavailable: {exc}")
    finally:
        DOWNSTREAM_REQUEST_DURATION_SECONDS.labels(
            service="api-service",
            downstream="data-service",
            method="GET",
            path="/users/{user_id}",
        ).observe(time.time() - started)

    if resp.status_code != 200:
        raise HTTPException(status_code=resp.status_code, detail=resp.text)

    payload = resp.json()
    return {
        "authenticated_as": claims.get("sub"),
        "user": payload.get("data"),
        "db_latency_ms": payload.get("db_latency_ms"),
    }


@app.get("/users")
def users(limit: int = 50, offset: int = 0, authorization: str | None = Header(default=None)) -> dict:
    enforce_rate_limit()
    claims = decode_token(authorization)
    started = time.time()

    try:
        resp = requests.get(
            f"{DATA_SERVICE_URL}/users",
            params={"limit": limit, "offset": offset},
            timeout=3,
        )
    except requests.RequestException as exc:
        raise HTTPException(status_code=503, detail=f"data-service unavailable: {exc}")
    finally:
        DOWNSTREAM_REQUEST_DURATION_SECONDS.labels(
            service="api-service",
            downstream="data-service",
            method="GET",
            path="/users",
        ).observe(time.time() - started)

    if resp.status_code != 200:
        raise HTTPException(status_code=resp.status_code, detail=resp.text)

    payload = resp.json()
    return {
        "authenticated_as": claims.get("sub"),
        "users": payload.get("data", []),
        "count": payload.get("count", 0),
        "limit": payload.get("limit", limit),
        "offset": payload.get("offset", offset),
        "db_latency_ms": payload.get("db_latency_ms"),
    }


@app.post("/users")
def create_user(payload: CreateUserRequest, authorization: str | None = Header(default=None)) -> dict:
    enforce_rate_limit()
    claims = decode_token(authorization)
    started = time.time()

    try:
        resp = requests.post(
            f"{DATA_SERVICE_URL}/users",
            json={"username": payload.username, "email": payload.email},
            timeout=3,
        )
    except requests.RequestException as exc:
        raise HTTPException(status_code=503, detail=f"data-service unavailable: {exc}")
    finally:
        DOWNSTREAM_REQUEST_DURATION_SECONDS.labels(
            service="api-service",
            downstream="data-service",
            method="POST",
            path="/users",
        ).observe(time.time() - started)

    if resp.status_code != 200:
        raise HTTPException(status_code=resp.status_code, detail=resp.text)

    result = resp.json()
    return {
        "authenticated_as": claims.get("sub"),
        "user": result.get("data"),
        "db_latency_ms": result.get("db_latency_ms"),
    }
