"""
Performance optimization module for OpenHands server.
This module provides middleware and utilities to improve server performance.
"""
import gzip
import time
from typing import Callable, List, Optional, Set

from fastapi import FastAPI, Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import ASGIApp


class CompressionMiddleware(BaseHTTPMiddleware):
    """
    Middleware to compress responses using gzip.
    """
    def __init__(
        self, 
        app: ASGIApp, 
        minimum_size: int = 500, 
        compressible_types: Optional[Set[str]] = None
    ):
        super().__init__(app)
        self.minimum_size = minimum_size
        self.compressible_types = compressible_types or {
            'text/html', 'text/css', 'text/javascript', 'application/javascript',
            'application/json', 'text/plain', 'text/xml', 'application/xml'
        }

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        response = await call_next(request)
        
        # Check if client accepts gzip encoding
        accept_encoding = request.headers.get('Accept-Encoding', '')
        
        if (
            'gzip' in accept_encoding and 
            response.headers.get('Content-Type', '').split(';')[0] in self.compressible_types and
            not response.headers.get('Content-Encoding') and
            response.body and
            len(response.body) > self.minimum_size
        ):
            # Compress the response body
            compressed_body = gzip.compress(response.body)
            response.body = compressed_body
            response.headers['Content-Encoding'] = 'gzip'
            response.headers['Content-Length'] = str(len(compressed_body))
            
        return response


class CacheHeadersMiddleware(BaseHTTPMiddleware):
    """
    Middleware to add optimized cache headers for static assets.
    """
    def __init__(
        self, 
        app: ASGIApp, 
        static_paths: List[str] = None,
        max_age: int = 604800  # 1 week in seconds
    ):
        super().__init__(app)
        self.static_paths = static_paths or ['/assets/', '/static/', '/favicon.ico']
        self.max_age = max_age

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        response = await call_next(request)
        
        # Check if the request path is for static assets
        is_static = any(request.url.path.startswith(path) for path in self.static_paths)
        
        if is_static:
            # Set aggressive caching for static assets
            response.headers['Cache-Control'] = f'public, max-age={self.max_age}, immutable'
        else:
            # For non-static assets, use no-cache
            response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate, max-age=0'
            response.headers['Pragma'] = 'no-cache'
            response.headers['Expires'] = '0'
            
        return response


class RequestTimingMiddleware(BaseHTTPMiddleware):
    """
    Middleware to track request timing for performance monitoring.
    """
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        start_time = time.time()
        response = await call_next(request)
        process_time = time.time() - start_time
        
        # Add timing header (visible only in development)
        response.headers['X-Process-Time'] = str(process_time)
        
        return response


def apply_performance_optimizations(app: FastAPI) -> None:
    """
    Apply all performance optimizations to the FastAPI app.
    """
    # Add compression middleware
    app.add_middleware(CompressionMiddleware)
    
    # Add optimized cache headers middleware
    app.add_middleware(
        CacheHeadersMiddleware, 
        static_paths=['/assets/', '/static/', '/favicon.ico']
    )
    
    # Add request timing middleware
    app.add_middleware(RequestTimingMiddleware)