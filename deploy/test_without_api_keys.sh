#!/bin/bash
# Test Script for OpenHands without API Keys
# This script runs OpenHands with a mock LLM for testing purposes

set -e

# Configuration
BACKEND_PORT=3000
FRONTEND_PORT=3001

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Python 3 is not installed. Please install it first.${NC}"
    exit 1
fi

# Check if Poetry is installed
if ! command -v poetry &> /dev/null; then
    echo -e "${RED}Poetry is not installed. Please install it first.${NC}"
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo -e "${RED}Node.js is not installed. Please install it first.${NC}"
    exit 1
fi

# Build the application
echo -e "${YELLOW}Building the application...${NC}"
cd "$(dirname "$0")/.."
make build

# Create a mock LLM server
echo -e "${YELLOW}Creating mock LLM server...${NC}"
cat > mock_llm_server.py << EOF
#!/usr/bin/env python3
"""
Mock LLM Server for testing OpenHands without API keys.
This provides a simple API compatible with OpenAI's API.
"""
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

class MockLLMHandler(BaseHTTPRequestHandler):
    def _set_headers(self, content_type="application/json"):
        self.send_response(200)
        self.send_header('Content-type', content_type)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_OPTIONS(self):
        self._set_headers()
        
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        request = json.loads(post_data.decode('utf-8'))
        
        # Simulate processing time
        time.sleep(0.5)
        
        if self.path == '/v1/chat/completions':
            response = self._handle_chat_completion(request)
        elif self.path == '/v1/completions':
            response = self._handle_completion(request)
        else:
            response = {"error": "Unsupported endpoint"}
        
        self._set_headers()
        self.wfile.write(json.dumps(response).encode('utf-8'))
    
    def _handle_chat_completion(self, request):
        messages = request.get('messages', [])
        last_message = messages[-1] if messages else {"content": ""}
        content = last_message.get('content', "")
        
        # Generate a mock response based on the input
        response_text = f"This is a mock response to: {content[:50]}..."
        
        return {
            "id": "mock-chat-completion-id",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": request.get('model', 'mock-model'),
            "choices": [
                {
                    "index": 0,
                    "message": {
                        "role": "assistant",
                        "content": response_text
                    },
                    "finish_reason": "stop"
                }
            ],
            "usage": {
                "prompt_tokens": len(content),
                "completion_tokens": len(response_text),
                "total_tokens": len(content) + len(response_text)
            }
        }
    
    def _handle_completion(self, request):
        prompt = request.get('prompt', "")
        
        # Generate a mock response based on the input
        response_text = f"This is a mock completion for: {prompt[:50]}..."
        
        return {
            "id": "mock-completion-id",
            "object": "text_completion",
            "created": int(time.time()),
            "model": request.get('model', 'mock-model'),
            "choices": [
                {
                    "text": response_text,
                    "index": 0,
                    "logprobs": None,
                    "finish_reason": "stop"
                }
            ],
            "usage": {
                "prompt_tokens": len(prompt),
                "completion_tokens": len(response_text),
                "total_tokens": len(prompt) + len(response_text)
            }
        }

def run_server(port=5001):
    server_address = ('', port)
    httpd = HTTPServer(server_address, MockLLMHandler)
    print(f"Starting mock LLM server on port {port}...")
    httpd.serve_forever()

if __name__ == "__main__":
    run_server()
EOF

# Make the mock LLM server executable
chmod +x mock_llm_server.py

# Create a temporary config file for testing
echo -e "${YELLOW}Creating temporary config file...${NC}"
cat > config.test.toml << EOF
[core]
workspace_base="./workspace"

[llm]
model="gpt-4"
api_key="mock-api-key"
base_url="http://localhost:5001/v1/"

[server]
host="0.0.0.0"
port=${BACKEND_PORT}
EOF

# Start the mock LLM server in the background
echo -e "${YELLOW}Starting mock LLM server...${NC}"
python3 mock_llm_server.py &
MOCK_SERVER_PID=$!

# Wait for the mock server to start
sleep 2

# Start the backend with the test config
echo -e "${YELLOW}Starting backend with mock LLM...${NC}"
OPENHANDS_CONFIG=config.test.toml poetry run uvicorn openhands.server.listen:app --host 0.0.0.0 --port ${BACKEND_PORT} &
BACKEND_PID=$!

# Wait for the backend to start
sleep 5

# Start the frontend
echo -e "${YELLOW}Starting frontend...${NC}"
cd frontend && VITE_BACKEND_HOST="localhost:${BACKEND_PORT}" VITE_FRONTEND_PORT="${FRONTEND_PORT}" npm run dev -- --port ${FRONTEND_PORT} --host 0.0.0.0 &
FRONTEND_PID=$!

# Wait for the frontend to start
sleep 5

echo -e "${GREEN}Test environment is running!${NC}"
echo -e "Backend is available at: ${GREEN}http://localhost:${BACKEND_PORT}${NC}"
echo -e "Frontend is available at: ${GREEN}http://localhost:${FRONTEND_PORT}${NC}"
echo -e "Using mock LLM server at: ${GREEN}http://localhost:5001${NC}"
echo -e "\n${YELLOW}Press Ctrl+C to stop all services${NC}"

# Function to clean up processes on exit
cleanup() {
    echo -e "\n${YELLOW}Stopping services...${NC}"
    kill $FRONTEND_PID $BACKEND_PID $MOCK_SERVER_PID 2>/dev/null || true
    echo -e "${GREEN}All services stopped.${NC}"
    exit 0
}

# Set up trap to catch Ctrl+C
trap cleanup INT

# Wait for user to press Ctrl+C
wait