"""
FastAPI application for website health checking.
"""
import os
from typing import Optional

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel

from app.health_checker import perform_health_check, HealthCheckError


# Initialize FastAPI app
app = FastAPI(
    title="Website Health Checker",
    description="API for checking website health including HTTP status, SSL certificate, and response time",
    version="1.0.0"
)

# Initialize templates
templates = Jinja2Templates(directory="templates")

# Serve static assets
app.mount("/static", StaticFiles(directory="static"), name="static")


class HealthCheckResponse(BaseModel):
    """Response model for health check endpoint."""
    url: str
    status_code: int
    response_time_ms: float
    ssl_valid: Optional[bool]
    ssl_expires: Optional[int]
    timestamp: str


class ErrorResponse(BaseModel):
    """Error response model."""
    detail: str
    error: Optional[str] = None


@app.get("/", tags=["UI"])
async def root(request: Request):
    """
    Serve the web UI.
    """
    return templates.TemplateResponse("index.html", {"request": request})


@app.get("/api", tags=["Root"])
async def api_info():
    """
    API information endpoint.
    """
    return {
        "message": "Website Health Checker API",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health?url=<website_url>",
            "docs": "/docs",
            "ping": "/ping"
        },
        "usage": "GET /health?url=https://example.com"
    }


@app.get(
    "/health",
    response_model=HealthCheckResponse,
    responses={400: {"model": ErrorResponse}, 500: {"model": ErrorResponse}},
    tags=["Health Check"]
)
async def health_check(
    url: str = Query(
        ...,
        description="URL to check health for (e.g., https://example.com)",
        examples="https://example.com"
    )
):
    """
    Perform health check on the specified URL.

    Returns comprehensive health information including:
    - HTTP status code
    - Response time in milliseconds
    - SSL certificate validity
    - Days until SSL expiration
    """
    try:
        # Get timeout from environment variable or use default
        timeout = int(os.getenv('HEALTH_CHECK_TIMEOUT', '10'))

        # Perform health check
        result = perform_health_check(url, timeout)

        return result

    except HealthCheckError as e:
        raise HTTPException(
            status_code=400,
            detail=str(e),
            headers={"X-Error": "Health Check Failed"}
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail="Internal server error",
            headers={"X-Error": str(e)}
        )


@app.get("/health/async", tags=["Health Check"])
async def async_health_check(
    url: str = Query(
        ...,
        description="URL to check health for (e.g., https://example.com)",
        examples="https://example.com"
    )
):
    """
    Alternative async endpoint for health checks.
    This endpoint demonstrates async support in FastAPI.
    """
    return await health_check(url=url)


# Health check endpoint for load balancers
@app.get("/ping", tags=["Health"])
async def ping():
    """
    Simple health check for load balancers/container orchestration.
    """
    return {"status": "healthy"}


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv('PORT', '8000'))
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=port,
        reload=os.getenv('DEBUG', 'False').lower() == 'true'
    )
