from datetime import datetime, timedelta, timezone
import os
import time

from fastapi import FastAPI, HTTPException, Request, Response
from pydantic import BaseModel
import jwt
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

app = FastAPI(title="auth-service", version="1.0.0")

JWT_SECRET = os.getenv("JWT_SECRET", "mubench-dev-secret")
JWT_ALGORITHM = "HS256"
JWT_EXPIRE_MINUTES = int(os.getenv("JWT_EXPIRE_MINUTES", "30"))

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


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    service = "auth-service"
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


class LoginRequest(BaseModel):
    username: str
    password: str


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_at: str


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "service": "auth-service"}


@app.get("/metrics")
def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.post("/login", response_model=LoginResponse)
def login(payload: LoginRequest) -> LoginResponse:
    # Demo credentials for benchmark scenarios.
    if payload.username != "demo" or payload.password != "demo123":
        raise HTTPException(status_code=401, detail="invalid credentials")

    now = datetime.now(tz=timezone.utc)
    exp = now + timedelta(minutes=JWT_EXPIRE_MINUTES)
    token = jwt.encode(
        {
            "sub": payload.username,
            "scope": "user",
            "iat": int(now.timestamp()),
            "exp": int(exp.timestamp()),
        },
        JWT_SECRET,
        algorithm=JWT_ALGORITHM,
    )

    return LoginResponse(access_token=token, expires_at=exp.isoformat())
