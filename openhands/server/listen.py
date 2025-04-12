import socketio

from openhands.server.app import app as base_app
from openhands.server.listen_socket import sio
from openhands.server.middleware import (
    AttachConversationMiddleware,
    InMemoryRateLimiter,
    LocalhostCORSMiddleware,
    ProviderTokenMiddleware,
    RateLimitMiddleware,
)
from openhands.server.performance import apply_performance_optimizations
from openhands.server.static import SPAStaticFiles

# Mount static files with optimized configuration
base_app.mount(
    '/', SPAStaticFiles(directory='./frontend/build', html=True), name='dist'
)

# Apply CORS middleware with optimized settings
base_app.add_middleware(
    LocalhostCORSMiddleware,
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)

# Apply performance optimizations (includes improved caching)
apply_performance_optimizations(base_app)

# Apply rate limiting with increased limits for better performance
base_app.add_middleware(
    RateLimitMiddleware,
    rate_limiter=InMemoryRateLimiter(requests=20, seconds=1),  # Doubled rate limit
)

# Apply conversation middleware
base_app.middleware('http')(AttachConversationMiddleware(base_app))
base_app.middleware('http')(ProviderTokenMiddleware(base_app))

# Create the ASGI app with optimized settings
app = socketio.ASGIApp(sio, other_asgi_app=base_app)
