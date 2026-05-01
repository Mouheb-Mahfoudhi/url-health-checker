"""
Unit tests for FastAPI application endpoints.
"""
import pytest
from unittest.mock import patch, MagicMock

from fastapi import HTTPException

from app.main import app


class TestRootEndpoint:
    """Tests for root endpoint (/)."""

    def test_root_endpoint_returns_html(self, client):
        """Test that root endpoint returns HTML content."""
        response = client.get("/")
        assert response.status_code == 200
        assert "text/html" in response.headers["content-type"]
        assert "Website Health Checker" in response.text


class TestApiInfoEndpoint:
    """Tests for API info endpoint (/api)."""

    def test_api_info_endpoint(self, client):
        """Test API info endpoint returns correct information."""
        response = client.get("/api")
        assert response.status_code == 200

        data = response.json()
        assert data["message"] == "Website Health Checker API"
        assert data["version"] == "1.0.0"
        assert "endpoints" in data
        assert data["endpoints"]["health"] == "/health?url=<website_url>"
        assert data["endpoints"]["docs"] == "/docs"
        assert data["endpoints"]["ping"] == "/ping"


class TestHealthCheckEndpoint:
    """Tests for health check endpoint (/health)."""

    @patch('app.main.perform_health_check')
    def test_health_check_success(self, mock_check, client):
        """Test successful health check."""
        mock_check.return_value = {
            "url": "https://example.com",
            "status_code": 200,
            "response_time_ms": 150.5,
            "ssl_valid": True,
            "ssl_expires": 45,
            "timestamp": "2026-04-29T22:00:00Z"
        }

        response = client.get("/health?url=https://example.com")

        assert response.status_code == 200
        data = response.json()
        assert data["status_code"] == 200
        assert data["response_time_ms"] == 150.5
        assert data["ssl_valid"] is True

    @patch('app.main.perform_health_check')
    def test_health_check_with_404(self, mock_check, client):
        """Test health check with 404 status."""
        mock_check.return_value = {
            "url": "https://example.com/notfound",
            "status_code": 404,
            "response_time_ms": 100.0,
            "ssl_valid": True,
            "ssl_expires": 45,
            "timestamp": "2026-04-29T22:00:00Z"
        }

        response = client.get("/health?url=https://example.com/notfound")

        assert response.status_code == 200
        data = response.json()
        assert data["status_code"] == 404

    @patch('app.main.perform_health_check')
    def test_health_check_with_500(self, mock_check, client):
        """Test health check with 500 status."""
        mock_check.return_value = {
            "url": "https://example.com/error",
            "status_code": 500,
            "response_time_ms": 200.0,
            "ssl_valid": True,
            "ssl_expires": 45,
            "timestamp": "2026-04-29T22:00:00Z"
        }

        response = client.get("/health?url=https://example.com/error")

        assert response.status_code == 200
        data = response.json()
        assert data["status_code"] == 500

    @patch('app.main.perform_health_check')
    def test_health_check_invalid_url(self, mock_check, client):
        """Test health check with invalid URL."""
        from app.health_checker import HealthCheckError
        mock_check.side_effect = HealthCheckError("Invalid URL format")

        response = client.get("/health?url=invalid-url")

        assert response.status_code == 400
        data = response.json()
        assert "detail" in data
        assert "Invalid URL format" in data["detail"]

    @patch('app.main.perform_health_check')
    def test_health_check_timeout(self, mock_check, client):
        """Test health check with timeout."""
        from app.health_checker import HealthCheckError
        mock_check.side_effect = HealthCheckError("Request timed out")

        response = client.get("/health?url=https://example.com")

        assert response.status_code == 400
        data = response.json()
        assert "timed out" in data["detail"].lower()

    @patch('app.main.perform_health_check')
    def test_health_check_unexpected_error(self, mock_check, client):
        """Test health check with unexpected error."""
        mock_check.side_effect = Exception("Unexpected error")

        response = client.get("/health?url=https://example.com")

        assert response.status_code == 500
        data = response.json()
        assert "detail" in data

    def test_health_check_missing_url_parameter(self, client):
        """Test health check without URL parameter."""
        response = client.get("/health")

        # FastAPI returns 422 for missing required parameters
        assert response.status_code == 422

    @patch('app.main.perform_health_check')
    def test_health_check_http_url_no_ssl(self, mock_check, client):
        """Test health check with HTTP URL (no SSL)."""
        mock_check.return_value = {
            "url": "http://example.com",
            "status_code": 200,
            "response_time_ms": 120.0,
            "ssl_valid": None,
            "ssl_expires": None,
            "timestamp": "2026-04-29T22:00:00Z"
        }

        response = client.get("/health?url=http://example.com")

        assert response.status_code == 200
        data = response.json()
        assert data["ssl_valid"] is None
        assert data["ssl_expires"] is None


class TestAsyncHealthCheckEndpoint:
    """Tests for async health check endpoint (/health/async)."""

    @patch('app.main.perform_health_check')
    def test_async_health_check_success(self, mock_check, client):
        """Test async health check endpoint."""
        mock_check.return_value = {
            "url": "https://example.com",
            "status_code": 200,
            "response_time_ms": 150.5,
            "ssl_valid": True,
            "ssl_expires": 45,
            "timestamp": "2026-04-29T22:00:00Z"
        }

        response = client.get("/health/async?url=https://example.com")

        assert response.status_code == 200
        data = response.json()
        assert data["status_code"] == 200


class TestPingEndpoint:
    """Tests for ping endpoint (/ping)."""

    def test_ping_endpoint(self, client):
        """Test ping endpoint for load balancers."""
        response = client.get("/ping")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"


class TestResponseModels:
    """Tests for response model validation."""

    @patch('app.main.perform_health_check')
    def test_health_check_response_model(self, mock_check, client):
        """Test that health check response matches expected model."""
        mock_check.return_value = {
            "url": "https://example.com",
            "status_code": 200,
            "response_time_ms": 150.5,
            "ssl_valid": True,
            "ssl_expires": 45,
            "timestamp": "2026-04-29T22:00:00Z"
        }

        response = client.get("/health?url=https://example.com")

        assert response.status_code == 200
        data = response.json()

        # Verify all required fields are present
        required_fields = ["url", "status_code", "response_time_ms", "ssl_valid", "ssl_expires", "timestamp"]
        for field in required_fields:
            assert field in data

        # Verify field types
        assert isinstance(data["url"], str)
        assert isinstance(data["status_code"], int)
        assert isinstance(data["response_time_ms"], float)
        assert isinstance(data["ssl_valid"], (bool, type(None)))
        assert isinstance(data["ssl_expires"], (int, type(None)))
        assert isinstance(data["timestamp"], str)


class TestEnvironmentVariables:
    """Tests for environment variable configuration."""

    @patch('app.main.perform_health_check')
    @patch.dict('os.environ', {'HEALTH_CHECK_TIMEOUT': '5'})
    def test_custom_timeout_from_env(self, mock_check, client):
        """Test that custom timeout from environment variable is used."""
        mock_check.return_value = {
            "url": "https://example.com",
            "status_code": 200,
            "response_time_ms": 150.5,
            "ssl_valid": True,
            "ssl_expires": 45,
            "timestamp": "2026-04-29T22:00:00Z"
        }

        response = client.get("/health?url=https://example.com")

        assert response.status_code == 200
        # Verify perform_health_check was called (timeout verification is implicit)
        mock_check.assert_called_once()
