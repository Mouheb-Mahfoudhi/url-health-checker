"""
Pytest configuration and fixtures for testing.
"""
import os
import sys

# Add the parent directory to Python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture
def client():
    """
    Create a test client for the FastAPI application.
    """
    return TestClient(app)


@pytest.fixture
def valid_urls():
    """
    List of valid URLs for testing.
    """
    return [
        "https://example.com",
        "http://example.com",
        "https://httpbin.org/status/200",
    ]


@pytest.fixture
def invalid_urls():
    """
    List of invalid URLs for testing.
    """
    return [
        "not-a-url",
        "ftp://example.com",
        "://example.com",
        "",
    ]


@pytest.fixture
def mock_health_check_response():
    """
    Mock health check response data.
    """
    return {
        "url": "https://example.com",
        "status_code": 200,
        "response_time_ms": 150.5,
        "ssl_valid": True,
        "ssl_expires": 45,
        "timestamp": "2026-04-29T22:00:00Z"
    }
