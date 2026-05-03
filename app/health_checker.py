"""
Health checker module for website health monitoring.
"""
import socket
import ssl
import time
import urllib.parse
from datetime import datetime, timezone
from typing import Dict, Optional

import httpx


class HealthCheckError(Exception):
    """Custom exception for health check errors."""
    pass


def validate_url(url: str) -> str:
    """
    Validate and normalize URL.

    Args:
        url: URL string to validate

    Returns:
        Normalized URL string

    Raises:
        HealthCheckError: If URL is invalid or doesn't use HTTP/HTTPS
    """
    try:
        parsed = urllib.parse.urlparse(url)
        if not parsed.scheme or parsed.scheme not in ['http', 'https']:
            raise HealthCheckError("URL must use HTTP or HTTPS protocol")
        if not parsed.netloc:
            raise HealthCheckError("Invalid URL format")
        return parsed.geturl()
    except Exception as e:
        if isinstance(e, HealthCheckError):
            raise
        raise HealthCheckError(f"Invalid URL: {str(e)}")


def check_http_status(url: str, timeout: int = 10) -> int:
    """
    Check HTTP status code of the given URL.

    Args:
        url: URL to check
        timeout: Request timeout in seconds

    Returns:
        HTTP status code

    Raises:
        HealthCheckError: If request fails
    """
    try:
        with httpx.Client(timeout=timeout, follow_redirects=True) as client:
            response = client.get(url)
            return response.status_code
    except httpx.TimeoutException:
        raise HealthCheckError("Request timed out")
    except httpx.HTTPStatusError as e:
        return e.response.status_code
    except Exception as e:
        raise HealthCheckError(f"HTTP request failed: {str(e)}")


def check_response_time(url: str, timeout: int = 10) -> float:
    """
    Measure response time for the given URL.

    Args:
        url: URL to check
        timeout: Request timeout in seconds

    Returns:
        Response time in milliseconds

    Raises:
        HealthCheckError: If request fails
    """
    try:
        with httpx.Client(timeout=timeout, follow_redirects=True) as client:
            start_time = time.time()
            client.get(url)
            end_time = time.time()
            return round((end_time - start_time) * 1000, 2)
    except Exception as e:
        raise HealthCheckError(f"Response time check failed: {str(e)}")


def check_ssl_certificate(url: str) -> Dict[str, Optional[bool | int]]:
    """
    Check SSL certificate validity for HTTPS URLs.

    Args:
        url: URL to check

    Returns:
        Dictionary with:
            - valid: Boolean indicating if SSL cert is valid
            - expires_in_days: Days until expiration (None if not HTTPS or error)

    Raises:
        HealthCheckError: If SSL check fails
    """
    parsed = urllib.parse.urlparse(url)

    # Only check SSL for HTTPS URLs
    if parsed.scheme != 'https':
        return {
            'valid': None,
            'expires_in_days': None
        }

    try:
        hostname = parsed.hostname
        port = parsed.port or 443

        # Create SSL context
        context = ssl.create_default_context()
        context.minimum_version = ssl.TLSVersion.TLSv1_2

        with socket.create_connection((hostname, port), timeout=10) as sock:
            with context.wrap_socket(sock, server_hostname=hostname) as secure_sock:
                cert = secure_sock.getpeercert()

        # Check if certificate is valid
        valid = True  # If we got here without exception, cert is valid

        # Calculate days until expiration
        from datetime import datetime
        expiry_str = cert['notAfter']
        expiry_date = datetime.strptime(expiry_str, '%b %d %H:%M:%S %Y %Z')
        expiry_date = expiry_date.replace(tzinfo=timezone.utc)

        days_until_expiry = (expiry_date - datetime.now(timezone.utc)).days

        return {
            'valid': valid,
            'expires_in_days': days_until_expiry
        }

    except Exception:
        # If SSL check fails, certificate is likely invalid
        return {
            'valid': False,
            'expires_in_days': None
        }


def perform_health_check(url: str, timeout: int = 30) -> Dict:
    """
    Perform comprehensive health check on a URL.

    Args:
        url: URL to check
        timeout: Request timeout in seconds

    Returns:
        Dictionary with all health check results
    """
    # Validate URL first
    validated_url = validate_url(url)

    # Perform all checks
    status_code = check_http_status(validated_url, timeout)
    response_time = check_response_time(validated_url, timeout)
    ssl_info = check_ssl_certificate(validated_url)

    return {
        'url': validated_url,
        'status_code': status_code,
        'response_time_ms': response_time,
        'ssl_valid': ssl_info['valid'],
        'ssl_expires': ssl_info['expires_in_days'],
        'timestamp': datetime.now(timezone.utc).isoformat()
    }
