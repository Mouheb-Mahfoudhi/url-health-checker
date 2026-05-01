"""
Unit tests for health_checker module.
"""
import pytest
from unittest.mock import patch, MagicMock
from datetime import datetime, timezone, timedelta

from app.health_checker import (
    validate_url,
    check_http_status,
    check_response_time,
    check_ssl_certificate,
    perform_health_check,
    HealthCheckError
)


class TestValidateUrl:
    """Tests for URL validation function."""

    def test_validate_valid_http_url(self):
        """Test validation of valid HTTP URL."""
        url = "http://example.com"
        result = validate_url(url)
        assert result == url

    def test_validate_valid_https_url(self):
        """Test validation of valid HTTPS URL."""
        url = "https://example.com"
        result = validate_url(url)
        assert result == url

    def test_validate_url_with_path(self):
        """Test validation of URL with path."""
        url = "https://example.com/path/to/resource"
        result = validate_url(url)
        assert result == url

    def test_validate_url_with_query_params(self):
        """Test validation of URL with query parameters."""
        url = "https://example.com?param=value"
        result = validate_url(url)
        assert "param=value" in result

    def test_validate_url_invalid_protocol(self):
        """Test that non-HTTP/HTTPS protocols raise error."""
        with pytest.raises(HealthCheckError, match="must use HTTP or HTTPS"):
            validate_url("ftp://example.com")

    def test_validate_url_no_protocol(self):
        """Test that URL without protocol raises error."""
        with pytest.raises(HealthCheckError):
            validate_url("example.com")

    def test_validate_url_empty(self):
        """Test that empty URL raises error."""
        with pytest.raises(HealthCheckError):
            validate_url("")

    def test_validate_url_no_netloc(self):
        """Test that URL without network location raises error."""
        with pytest.raises(HealthCheckError):
            validate_url("https://")


class TestCheckHttpStatus:
    """Tests for HTTP status check function."""

    @patch('app.health_checker.httpx.Client')
    def test_check_http_status_success(self, mock_client):
        """Test successful HTTP status check."""
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_client.return_value.__enter__.return_value.get.return_value = mock_response

        result = check_http_status("https://example.com")
        assert result == 200

    @patch('app.health_checker.httpx.Client')
    def test_check_http_status_404(self, mock_client):
        """Test HTTP status check with 404."""
        mock_response = MagicMock()
        mock_response.status_code = 404
        mock_client.return_value.__enter__.return_value.get.return_value = mock_response

        result = check_http_status("https://example.com")
        assert result == 404

    @patch('app.health_checker.httpx.Client')
    def test_check_http_status_timeout(self, mock_client):
        """Test HTTP status check with timeout."""
        import httpx
        mock_client.return_value.__enter__.return_value.get.side_effect = httpx.TimeoutException("Timeout")

        with pytest.raises(HealthCheckError, match="timed out"):
            check_http_status("https://example.com", timeout=1)

    @patch('app.health_checker.httpx.Client')
    def test_check_http_status_connection_error(self, mock_client):
        """Test HTTP status check with connection error."""
        mock_client.return_value.__enter__.return_value.get.side_effect = Exception("Connection error")

        with pytest.raises(HealthCheckError, match="HTTP request failed"):
            check_http_status("https://example.com")


class TestCheckResponseTime:
    """Tests for response time check function."""

    @patch('app.health_checker.httpx.Client')
    @patch('app.health_checker.time.time')
    def test_check_response_time_success(self, mock_time, mock_client):
        """Test successful response time check."""
        mock_time.side_effect = [0.0, 0.15]  # Start and end times
        mock_response = MagicMock()
        mock_client.return_value.__enter__.return_value.get.return_value = mock_response

        result = check_response_time("https://example.com")
        assert result == 150.0  # 150ms

    @patch('app.health_checker.httpx.Client')
    def test_check_response_time_error(self, mock_client):
        """Test response time check with error."""
        mock_client.return_value.__enter__.return_value.get.side_effect = Exception("Error")

        with pytest.raises(HealthCheckError, match="Response time check failed"):
            check_response_time("https://example.com")


class TestCheckSslCertificate:
    """Tests for SSL certificate check function."""

    def test_check_ssl_http_url(self):
        """Test SSL check returns None for HTTP URLs."""
        result = check_ssl_certificate("http://example.com")
        assert result['valid'] is None
        assert result['expires_in_days'] is None

    @patch('app.health_checker.socket.create_connection')
    @patch('app.health_checker.ssl.create_default_context')
    def test_check_ssl_valid_certificate(self, mock_ssl_context, mock_socket):
        """Test SSL check with valid certificate."""
        # Mock socket and SSL connection
        mock_sock = MagicMock()
        mock_socket.return_value.__enter__.return_value = mock_sock

        mock_secure_sock = MagicMock()
        mock_ssl_context.return_value.wrap_socket.return_value.__enter__.return_value = mock_secure_sock

        # Mock certificate with expiration date
        expiry_date = datetime.now(timezone.utc) + timedelta(days=45)
        mock_secure_sock.getpeercert.return_value = {
            'notAfter': expiry_date.strftime('%b %d %H:%M:%S %Y %Z')
        }

        result = check_ssl_certificate("https://example.com")
        assert result['valid'] is True
        # Allow for 1 day variance due to timing
        assert 44 <= result['expires_in_days'] <= 46

    @patch('app.health_checker.socket.create_connection')
    def test_check_ssl_connection_error(self, mock_socket):
        """Test SSL check with connection error."""
        mock_socket.return_value.__enter__.side_effect = Exception("Connection failed")

        result = check_ssl_certificate("https://example.com")
        assert result['valid'] is False
        assert result['expires_in_days'] is None


class TestPerformHealthCheck:
    """Tests for comprehensive health check function."""

    @patch('app.health_checker.check_ssl_certificate')
    @patch('app.health_checker.check_response_time')
    @patch('app.health_checker.check_http_status')
    @patch('app.health_checker.validate_url')
    def test_perform_health_check_success(self, mock_validate, mock_status, mock_time, mock_ssl):
        """Test successful comprehensive health check."""
        mock_validate.return_value = "https://example.com"
        mock_status.return_value = 200
        mock_time.return_value = 150.5
        mock_ssl.return_value = {'valid': True, 'expires_in_days': 45}

        result = perform_health_check("https://example.com")

        assert result['url'] == "https://example.com"
        assert result['status_code'] == 200
        assert result['response_time_ms'] == 150.5
        assert result['ssl_valid'] is True
        assert result['ssl_expires'] == 45
        assert 'timestamp' in result

    def test_perform_health_check_invalid_url(self):
        """Test health check with invalid URL."""
        with patch('app.health_checker.validate_url') as mock_validate:
            mock_validate.side_effect = HealthCheckError("Invalid URL")

            with pytest.raises(HealthCheckError, match="Invalid URL"):
                perform_health_check("invalid-url")
