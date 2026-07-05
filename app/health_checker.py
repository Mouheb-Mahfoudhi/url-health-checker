"""
Health checker module for website health monitoring.
"""
import logging
import http.client
import socket
import ssl
import time
import urllib.parse
from datetime import datetime, timezone
from typing import Dict, Optional

import httpx


logger = logging.getLogger(__name__)


class HealthCheckError(Exception):
    """Custom exception for health check errors."""
    pass


def _build_unverified_ssl_context() -> ssl.SSLContext:
    """Create an SSL context that skips certificate verification for fallback requests."""
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    return context


def _fetch_status_code_and_time(url: str, timeout: int) -> tuple[int, float]:
    """Fetch a URL and return status code plus elapsed time without failing on bad TLS certs."""
    parsed = urllib.parse.urlparse(url)
    connection_class = http.client.HTTPSConnection if parsed.scheme == "https" else http.client.HTTPConnection
    connection_kwargs = {"timeout": timeout}

    if parsed.scheme == "https":
        connection_kwargs["context"] = _build_unverified_ssl_context()

    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"

    connection = connection_class(parsed.hostname, parsed.port or (443 if parsed.scheme == "https" else 80), **connection_kwargs)
    start_time = time.time()

    try:
        connection.request("GET", path, headers={"User-Agent": "url-health-checker/1.0"})
        response = connection.getresponse()
        response.read()
        elapsed_ms = round((time.time() - start_time) * 1000, 2)
        return response.status, elapsed_ms
    finally:
        connection.close()


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
        logger.warning("http_check_timeout", extra={"url": url, "timeout": timeout})
        raise HealthCheckError("Request timed out")
    except httpx.HTTPError as e:
        if urllib.parse.urlparse(url).scheme == "https":
            try:
                status_code, _ = _fetch_status_code_and_time(url, timeout)
                return status_code
            except Exception as fallback_error:
                logger.error(
                    "http_check_failed",
                    extra={
                        "url": url,
                        "error": str(fallback_error),
                        "error_type": fallback_error.__class__.__name__,
                    },
                )
                raise HealthCheckError(f"HTTP request failed: {str(e)}")
        logger.error(
            "http_check_failed",
            extra={"url": url, "error": str(e), "error_type": e.__class__.__name__},
        )
        raise HealthCheckError(f"HTTP request failed: {str(e)}")
    except httpx.HTTPStatusError as e:
        return e.response.status_code
    except Exception as e:
        logger.error(
            "http_check_failed",
            extra={"url": url, "error": str(e), "error_type": e.__class__.__name__},
        )
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
    except httpx.HTTPError as e:
        if urllib.parse.urlparse(url).scheme == "https":
            try:
                _, elapsed_ms = _fetch_status_code_and_time(url, timeout)
                return elapsed_ms
            except Exception as fallback_error:
                logger.error(
                    "response_time_check_failed",
                    extra={
                        "url": url,
                        "error": str(fallback_error),
                        "error_type": fallback_error.__class__.__name__,
                    },
                )
                raise HealthCheckError(f"Response time check failed: {str(e)}")
        logger.error(
            "response_time_check_failed",
            extra={"url": url, "error": str(e), "error_type": e.__class__.__name__},
        )
        raise HealthCheckError(f"Response time check failed: {str(e)}")
    except Exception as e:
        logger.error(
            "response_time_check_failed",
            extra={"url": url, "error": str(e), "error_type": e.__class__.__name__},
        )
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

        def read_certificate(context: ssl.SSLContext) -> Dict[str, Optional[bool | int]]:
            with socket.create_connection((hostname, port), timeout=10) as sock:
                with context.wrap_socket(sock, server_hostname=hostname) as secure_sock:
                    cert = secure_sock.getpeercert()

            expiry_str = cert['notAfter']
            expiry_date = datetime.strptime(expiry_str, '%b %d %H:%M:%S %Y %Z')
            expiry_date = expiry_date.replace(tzinfo=timezone.utc)

            return {
                'valid': True,
                'expires_in_days': (expiry_date - datetime.now(timezone.utc)).days
            }

        # First try a verified TLS handshake so we can report a valid certificate.
        try:
            context = ssl.create_default_context()
            context.minimum_version = ssl.TLSVersion.TLSv1_2
            return read_certificate(context)
        except Exception:
            # Fall back to an unverified handshake so expired/self-signed certs still return data.
            fallback_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            fallback_context.check_hostname = False
            fallback_context.verify_mode = ssl.CERT_NONE
            fallback_context.minimum_version = ssl.TLSVersion.TLSv1_2

            certificate_data = read_certificate(fallback_context)
            certificate_data['valid'] = False
            return certificate_data

    except Exception:
        logger.warning("ssl_check_failed", extra={"url": url})
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
