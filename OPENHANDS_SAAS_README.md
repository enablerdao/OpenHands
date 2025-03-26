# OpenHands SaaS プロジェクト

このプロジェクトは、OpenHandsをSaaSとして提供するためのマルチテナント環境を構築します。

## アーキテクチャ概要

- **リバースプロキシサーバー**: ユーザー認証とリクエストのルーティングを担当
- **認証サーバー**: ユーザー認証とセッション管理を担当
- **OpenHandsインスタンス**: 各テナント（ユーザー）専用のOpenHandsインスタンス

## セットアップ手順

### 1. EC2インスタンスの準備

以下のスクリプトを使用して、EC2インスタンスを管理します：

```bash
#!/bin/bash

# === CONFIG ==============================
REGION="ap-northeast-1"
KEY_NAME="openhands-key"
KEY_PATH="$HOME/.ssh/${KEY_NAME}.pem"
SECURITY_GROUP="openhands-sg"
INSTANCE_TAG="OpenHands"
INSTANCE_TYPE="t3a.large"  # 大きめに変更
VOLUME_SIZE=30  # ディスク30GB
# 最新 Amazon Linux 2 AMI を取得
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate)[-1].ImageId' \
  --output text --region "$REGION")
# =========================================
```

### 2. リバースプロキシサーバーのセットアップ

#### 2.1 Nginxのインストール

```bash
sudo amazon-linux-extras install nginx1 -y
sudo systemctl enable nginx
sudo systemctl start nginx
```

#### 2.2 SSL証明書の設定

```bash
sudo mkdir -p /etc/letsencrypt/live/openhands-saas/
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/letsencrypt/live/openhands-saas/privkey.pem \
  -out /etc/letsencrypt/live/openhands-saas/fullchain.pem \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=OpenHands/OU=SaaS/CN=openhands-saas.example.com"
```

#### 2.3 認証サーバーのセットアップ

```bash
sudo pip3 install flask flask-cors
```

認証サーバーのコード（`/usr/local/bin/auth-server.py`）:

```python
#!/usr/bin/env python3
import json
import logging
import os
import hashlib
import time
from flask import Flask, request, jsonify
from flask_cors import CORS

# ログ設定
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(filename)s:%(lineno)d - %(message)s',
    handlers=[
        logging.FileHandler("/var/log/auth-server.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("auth-server")

app = Flask(__name__)
CORS(app)

# 簡易的なユーザーデータベース
USERS = {
    "user1": {"password": "password1", "name": "User 1"},
    "user2": {"password": "password2", "name": "User 2"}
}

# セッション管理（本番環境では永続化が必要）
SESSIONS = {}

@app.route('/login', methods=['POST'])
def login():
    logger.info(f"POST request: {request.path}")
    
    # リクエストデータの取得
    data = request.get_json()
    logger.info(f"POST data: {json.dumps(data)}")
    
    username = data.get('username')
    password = data.get('password')
    
    logger.info(f"Login attempt for user: {username}")
    
    # 認証チェック
    if username in USERS and USERS[username]["password"] == password:
        # セッションIDの生成
        session_id = hashlib.md5(f"{username}:{time.time()}".encode()).hexdigest()
        SESSIONS[session_id] = {"username": username, "timestamp": time.time()}
        
        logger.info(f"Login successful for user: {username}, session: {session_id}")
        
        # クッキーとJSONレスポンスを返す
        response = jsonify({"success": True, "message": "Login successful"})
        response.set_cookie('session_id', session_id, httponly=True, secure=True)
        return response
    else:
        logger.info(f"Login failed for user: {username}")
        return jsonify({"success": False, "message": "Invalid username or password"}), 401

@app.route('/auth', methods=['GET'])
def auth():
    logger.info(f"GET request: {request.path}")
    
    # セッションIDの取得
    session_id = request.cookies.get('session_id')
    logger.info(f"Auth request with session_id: {session_id}")
    
    # セッションの検証
    if session_id and session_id in SESSIONS:
        username = SESSIONS[session_id]["username"]
        logger.info(f"Auth successful for user: {username}")
        
        # 認証成功
        response = jsonify({"authenticated": True, "username": username})
        response.headers['X-User-ID'] = username
        return response
    else:
        logger.info("Auth failed: No valid session")
        # 認証失敗
        return jsonify({"authenticated": False, "message": "Not authenticated"}), 401

@app.route('/logout', methods=['POST'])
def logout():
    logger.info(f"POST request: {request.path}")
    
    # セッションIDの取得
    session_id = request.cookies.get('session_id')
    
    # セッションの削除
    if session_id and session_id in SESSIONS:
        username = SESSIONS[session_id]["username"]
        del SESSIONS[session_id]
        logger.info(f"Logout successful for user: {username}")
        
        # クッキーを削除してレスポンスを返す
        response = jsonify({"success": True, "message": "Logout successful"})
        response.set_cookie('session_id', '', expires=0)
        return response
    else:
        logger.info("Logout failed: No valid session")
        return jsonify({"success": False, "message": "Not authenticated"}), 401

if __name__ == '__main__':
    logger.info(f"Starting auth server on port 8080...")
    app.run(host='127.0.0.1', port=8080)
```

認証サーバーをサービスとして登録：

```bash
sudo tee /etc/systemd/system/auth-server.service > /dev/null << 'EOF'
[Unit]
Description=OpenHands SaaS Authentication Server
After=network.target

[Service]
ExecStart=/usr/local/bin/auth-server.py
Restart=always
User=nginx
Group=nginx
Environment=PATH=/usr/bin:/usr/local/bin
WorkingDirectory=/tmp

[Install]
WantedBy=multi-user.target
EOF

sudo chmod +x /usr/local/bin/auth-server.py
sudo systemctl daemon-reload
sudo systemctl enable auth-server
sudo systemctl start auth-server
```

#### 2.4 Nginxの設定

```bash
sudo tee /etc/nginx/conf.d/openhands-proxy.conf > /dev/null << 'EOF'
# OpenHands SaaS リバースプロキシ設定

# ユーザーマッピング用のマップ
map $cookie_session_id $user_from_session {
    default "";
    # 実際の環境では、ここにセッションIDからユーザーIDへのマッピングが必要
    # MVPでは簡易的に実装
    "~.*" $http_x_user_id;
}

# アップストリームサーバーの定義
upstream openhands-saas-instance-1 {
    server 52.195.93.27:3000;
}

upstream openhands-saas-instance-2 {
    server 54.95.198.182:3000;
}

# HTTPサーバー設定
server {
    listen 80;
    server_name _;  # すべてのホスト名に対応

    # HTTPSにリダイレクト
    return 301 https://$host$request_uri;
}

# HTTPSサーバー設定
server {
    listen 443 ssl;
    server_name _;

    ssl_certificate /etc/letsencrypt/live/openhands-saas/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/openhands-saas/privkey.pem;

    # 文字エンコーディングの設定
    charset utf-8;
    source_charset utf-8;

    # ルートへのアクセス
    location / {
        # 認証チェック
        auth_request /auth;
        error_page 401 = /login/;

        # 認証成功時のプロキシ設定
        auth_request_set $auth_user_id $upstream_http_x_user_id;

        # ユーザーIDに基づいてバックエンドを選択
        set $backend "openhands-saas-instance-1";  # デフォルト

        if ($auth_user_id = "user1") {
            set $backend "openhands-saas-instance-1";
        }

        if ($auth_user_id = "user2") {
            set $backend "openhands-saas-instance-2";
        }

        # プロキシ設定
        proxy_pass http://$backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-User-ID $auth_user_id;

        # WebSocketのサポート
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # タイムアウト設定
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
        send_timeout 300;
    }

    # APIリクエスト
    location /api/ {
        # 認証チェック
        auth_request /auth;
        error_page 401 = /login/;

        # 認証成功時のプロキシ設定
        auth_request_set $auth_user_id $upstream_http_x_user_id;

        # ユーザーIDに基づいてバックエンドを選択
        set $backend "openhands-saas-instance-1";  # デフォルト

        if ($auth_user_id = "user1") {
            set $backend "openhands-saas-instance-1";
        }

        if ($auth_user_id = "user2") {
            set $backend "openhands-saas-instance-2";
        }

        # プロキシ設定
        proxy_pass http://$backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-User-ID $auth_user_id;
    }

    # WebSocket接続
    location /socket.io/ {
        # 認証チェック
        auth_request /auth;
        error_page 401 = /login/;

        # 認証成功時のプロキシ設定
        auth_request_set $auth_user_id $upstream_http_x_user_id;

        # ユーザーIDに基づいてバックエンドを選択
        set $backend "openhands-saas-instance-1";  # デフォルト

        if ($auth_user_id = "user1") {
            set $backend "openhands-saas-instance-1";
        }

        if ($auth_user_id = "user2") {
            set $backend "openhands-saas-instance-2";
        }

        # WebSocketプロキシ設定
        proxy_pass http://$backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-User-ID $auth_user_id;

        # タイムアウト設定
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
        proxy_read_timeout 300;
        send_timeout 300;
    }

    # 認証エンドポイント
    location = /auth {
        internal;
        proxy_pass http://127.0.0.1:8080/auth;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-URI $request_uri;
    }

    # ログインPOSTリクエスト
    location = /login {
        # GETリクエストの場合はリダイレクト
        if ($request_method = GET) {
            return 301 /login/;
        }

        # POSTリクエストの場合は認証サーバーに転送
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Content-Type "application/json";
    }

    # ログインページ
    location /login/ {
        root /var/www/html;
        index index.html;
        add_header Content-Type "text/html; charset=utf-8";
    }

    # 静的ファイル
    location /static/ {
        root /var/www/html;
    }
}
EOF

sudo nginx -t
sudo systemctl restart nginx
```

#### 2.5 ログインページの作成

```bash
sudo mkdir -p /var/www/html/login
sudo tee /var/www/html/login/index.html > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenHands SaaS - ログイン</title>
    <style>
        body {
            font-family: 'Helvetica Neue', Arial, sans-serif;
            margin: 0;
            padding: 0;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            background-color: #f5f5f5;
        }
        .login-container {
            background-color: white;
            padding: 2rem;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            width: 350px;
        }
        h1 {
            text-align: center;
            margin-bottom: 1.5rem;
            color: #4285f4;
        }
        .form-group {
            margin-bottom: 1rem;
        }
        label {
            display: block;
            margin-bottom: 0.5rem;
            font-weight: bold;
            color: #555;
        }
        input, select {
            width: 100%;
            padding: 0.75rem;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 1rem;
            box-sizing: border-box;
        }
        input:focus, select:focus {
            outline: none;
            border-color: #4285f4;
            box-shadow: 0 0 0 2px rgba(66, 133, 244, 0.2);
        }
        button {
            width: 100%;
            padding: 0.75rem;
            background-color: #4285f4;
            color: white;
            border: none;
            border-radius: 4px;
            font-size: 1rem;
            cursor: pointer;
            transition: background-color 0.3s;
        }
        button:hover {
            background-color: #3367d6;
        }
        .error-message {
            color: #d93025;
            margin-top: 1rem;
            text-align: center;
            display: none;
        }
        .back-link {
            text-align: center;
            margin-top: 1rem;
        }
        .back-link a {
            color: #4285f4;
            text-decoration: none;
        }
        .back-link a:hover {
            text-decoration: underline;
        }
        #debug-info {
            margin-top: 1rem;
            padding: 1rem;
            background-color: #f8f9fa;
            border-radius: 4px;
            font-size: 0.8rem;
            color: #666;
            white-space: pre-wrap;
            display: none;
        }
        .loading {
            display: none;
            text-align: center;
            margin-top: 1rem;
        }
        .loading-spinner {
            border: 4px solid #f3f3f3;
            border-top: 4px solid #4285f4;
            border-radius: 50%;
            width: 30px;
            height: 30px;
            animation: spin 1s linear infinite;
            margin: 0 auto;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        .demo-info {
            margin-top: 1rem;
            padding: 1rem;
            background-color: #f8f9fa;
            border-radius: 4px;
            font-size: 0.9rem;
            color: #666;
        }
        .demo-info h3 {
            margin-top: 0;
            color: #4285f4;
        }
        .demo-info p {
            margin: 0.5rem 0;
        }
        .demo-info code {
            background-color: #e9ecef;
            padding: 0.2rem 0.4rem;
            border-radius: 3px;
            font-family: monospace;
        }
    </style>
</head>
<body>
    <div class="login-container">
        <h1>OpenHands SaaS</h1>
        <form id="login-form">
            <div class="form-group">
                <label for="instance">インスタンス</label>
                <select id="instance" name="instance">
                    <option value="user1">インスタンス 1</option>
                    <option value="user2">インスタンス 2</option>
                </select>
            </div>
            <div class="form-group">
                <label for="password">パスワード</label>
                <input type="password" id="password" name="password" required>
            </div>
            <button type="submit">ログイン</button>
            <div id="loading" class="loading">
                <div class="loading-spinner"></div>
                <p>ログイン中...</p>
            </div>
            <div id="error-message" class="error-message">
                ユーザー名またはパスワードが正しくありません。
            </div>
            <div id="debug-info"></div>
        </form>
        <div class="demo-info">
            <h3>デモ用アカウント</h3>
            <p><strong>インスタンス 1:</strong> パスワード <code>password1</code></p>
            <p><strong>インスタンス 2:</strong> パスワード <code>password2</code></p>
        </div>
        <div class="back-link">
            <a href="/">トップページに戻る</a>
        </div>
    </div>

    <script>
        // デバッグ情報を表示する関数
        function showDebugInfo(message) {
            const debugInfo = document.getElementById('debug-info');
            debugInfo.style.display = 'block';
            debugInfo.textContent += message + '\n';
        }

        document.getElementById('login-form').addEventListener('submit', function(e) {
            e.preventDefault();
            
            const instance = document.getElementById('instance').value;
            const password = document.getElementById('password').value;
            
            // インスタンスに基づいてユーザー名を設定
            const username = instance;
            
            // ローディング表示
            document.getElementById('loading').style.display = 'block';
            document.getElementById('error-message').style.display = 'none';
            
            // デバッグ情報
            showDebugInfo('Sending login request for user: ' + username);
            
            // ログインリクエスト
            fetch('/login', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ username, password }),
                credentials: 'include'  // クッキーを含める
            })
            .then(response => {
                showDebugInfo('Response status: ' + response.status);
                return response.json().catch(error => {
                    showDebugInfo('Error parsing JSON: ' + error);
                    throw new Error('Invalid JSON response');
                });
            })
            .then(data => {
                showDebugInfo('Response data: ' + JSON.stringify(data));
                if (data.success) {
                    showDebugInfo('Login successful, redirecting to /');
                    
                    // ログイン成功後、少し待ってからリダイレクト
                    setTimeout(function() {
                        window.location.href = '/';
                    }, 1000);
                } else {
                    showDebugInfo('Login failed: ' + (data.message || 'Unknown error'));
                    document.getElementById('loading').style.display = 'none';
                    document.getElementById('error-message').style.display = 'block';
                }
            })
            .catch(error => {
                showDebugInfo('Error: ' + error.message);
                document.getElementById('loading').style.display = 'none';
                document.getElementById('error-message').style.display = 'block';
            });
        });
    </script>
</body>
</html>
EOF

sudo tee /var/www/html/index.html > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenHands SaaS - AIアシスタントプラットフォーム</title>
    <style>
        body {
            font-family: 'Helvetica Neue', Arial, sans-serif;
            margin: 0;
            padding: 0;
            color: #333;
            background-color: #f8f9fa;
        }
        header {
            background-color: #4285f4;
            color: white;
            padding: 1rem 0;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        }
        .header-container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 0 2rem;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .logo {
            font-size: 1.8rem;
            font-weight: bold;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 2rem;
        }
        .hero {
            text-align: center;
            padding: 3rem 0;
        }
        .hero h1 {
            font-size: 2.5rem;
            margin-bottom: 1rem;
            color: #333;
        }
        .hero p {
            font-size: 1.2rem;
            color: #666;
            max-width: 800px;
            margin: 0 auto 2rem;
            line-height: 1.6;
        }
        .cta-button {
            display: inline-block;
            background-color: #4285f4;
            color: white;
            padding: 0.8rem 2rem;
            font-size: 1.1rem;
            border-radius: 4px;
            text-decoration: none;
            transition: background-color 0.3s;
        }
        .cta-button:hover {
            background-color: #3367d6;
        }
        .features {
            display: flex;
            flex-wrap: wrap;
            justify-content: center;
            gap: 2rem;
            margin: 3rem 0;
        }
        .feature {
            flex: 1;
            min-width: 300px;
            background: white;
            padding: 1.5rem;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.05);
        }
        .feature h3 {
            color: #4285f4;
            margin-top: 0;
        }
        .feature p {
            color: #666;
            line-height: 1.6;
        }
        .feature-icon {
            font-size: 2.5rem;
            margin-bottom: 1rem;
            color: #4285f4;
        }
        .how-it-works {
            background-color: #e8f0fe;
            padding: 3rem 0;
            margin: 3rem 0;
        }
        .steps {
            display: flex;
            flex-wrap: wrap;
            justify-content: space-between;
            margin-top: 2rem;
        }
        .step {
            flex: 1;
            min-width: 250px;
            text-align: center;
            padding: 1rem;
        }
        .step-number {
            display: inline-block;
            width: 40px;
            height: 40px;
            background-color: #4285f4;
            color: white;
            border-radius: 50%;
            line-height: 40px;
            font-weight: bold;
            margin-bottom: 1rem;
        }
        .pricing {
            padding: 3rem 0;
        }
        .plans {
            display: flex;
            flex-wrap: wrap;
            justify-content: center;
            gap: 2rem;
            margin-top: 2rem;
        }
        .plan {
            flex: 1;
            min-width: 300px;
            background: white;
            padding: 2rem;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.05);
            text-align: center;
        }
        .plan h3 {
            color: #4285f4;
            margin-top: 0;
            font-size: 1.5rem;
        }
        .plan-price {
            font-size: 2.5rem;
            font-weight: bold;
            margin: 1rem 0;
        }
        .plan-price span {
            font-size: 1rem;
            font-weight: normal;
            color: #666;
        }
        .plan-features {
            list-style: none;
            padding: 0;
            margin: 1.5rem 0;
            text-align: left;
        }
        .plan-features li {
            padding: 0.5rem 0;
            border-bottom: 1px solid #eee;
        }
        .plan-features li:last-child {
            border-bottom: none;
        }
        .plan-features li::before {
            content: "✓";
            color: #4285f4;
            margin-right: 0.5rem;
        }
        footer {
            background-color: #333;
            color: white;
            text-align: center;
            padding: 1.5rem 0;
        }
        .login-button {
            color: white;
            text-decoration: none;
            padding: 0.5rem 1rem;
            border: 1px solid white;
            border-radius: 4px;
            transition: background-color 0.3s;
        }
        .login-button:hover {
            background-color: rgba(255,255,255,0.1);
        }
        .section-title {
            text-align: center;
            margin-bottom: 2rem;
        }
        .section-title h2 {
            font-size: 2rem;
            color: #333;
        }
        .section-title p {
            color: #666;
            max-width: 600px;
            margin: 0 auto;
        }
        .demo-note {
            background-color: #e8f0fe;
            padding: 1rem;
            border-radius: 4px;
            margin-top: 2rem;
            text-align: center;
        }
        .demo-note p {
            margin: 0;
            color: #4285f4;
        }
    </style>
</head>
<body>
    <header>
        <div class="header-container">
            <div class="logo">OpenHands SaaS</div>
            <a href="/login/" class="login-button">ログイン</a>
        </div>
    </header>

    <div class="container">
        <section class="hero">
            <h1>AIアシスタントを簡単に利用できるSaaSプラットフォーム</h1>
            <p>OpenHandsは、高度なAIアシスタント機能を提供するSaaSプラットフォームです。複雑な設定不要で、すぐにAIの力を活用できます。</p>
            <a href="/login/" class="cta-button">今すぐ始める</a>
        </section>

        <section class="features">
            <div class="feature">
                <div class="feature-icon">🚀</div>
                <h3>簡単操作</h3>
                <p>直感的なインターフェースで、AIアシスタントとのやり取りがスムーズに行えます。技術的な知識は必要ありません。</p>
            </div>
            <div class="feature">
                <div class="feature-icon">💡</div>
                <h3>高度な機能</h3>
                <p>コード生成、データ分析、文書作成など、様々なタスクをAIがサポートします。業務効率を大幅に向上させます。</p>
            </div>
            <div class="feature">
                <div class="feature-icon">🔒</div>
                <h3>セキュアな環境</h3>
                <p>データは暗号化され、安全に保管されます。プライバシーとセキュリティを最優先に設計されています。</p>
            </div>
        </section>

        <section class="how-it-works">
            <div class="container">
                <div class="section-title">
                    <h2>利用の流れ</h2>
                    <p>OpenHands SaaSは、簡単な3ステップで始められます。</p>
                </div>
                <div class="steps">
                    <div class="step">
                        <div class="step-number">1</div>
                        <h3>アカウント作成</h3>
                        <p>簡単な登録フォームに必要事項を入力するだけで、すぐにアカウントが作成できます。</p>
                    </div>
                    <div class="step">
                        <div class="step-number">2</div>
                        <h3>プラン選択</h3>
                        <p>ニーズに合わせて最適なプランを選択。いつでもアップグレード・ダウングレード可能です。</p>
                    </div>
                    <div class="step">
                        <div class="step-number">3</div>
                        <h3>AIと対話</h3>
                        <p>すぐにAIアシスタントとの対話を開始。質問、タスク依頼、アイデア出しなど様々な用途に活用できます。</p>
                    </div>
                </div>
            </div>
        </section>

        <section class="pricing">
            <div class="section-title">
                <h2>料金プラン</h2>
                <p>ニーズに合わせた柔軟なプランをご用意しています。</p>
            </div>
            <div class="plans">
                <div class="plan">
                    <h3>スタータープラン</h3>
                    <div class="plan-price">¥5,000<span>/月</span></div>
                    <ul class="plan-features">
                        <li>1ユーザーアカウント</li>
                        <li>月間1,000回の質問</li>
                        <li>基本的なAI機能</li>
                        <li>標準サポート</li>
                    </ul>
                    <a href="/login/" class="cta-button">選択する</a>
                </div>
                <div class="plan">
                    <h3>プロフェッショナルプラン</h3>
                    <div class="plan-price">¥15,000<span>/月</span></div>
                    <ul class="plan-features">
                        <li>5ユーザーアカウント</li>
                        <li>月間5,000回の質問</li>
                        <li>高度なAI機能</li>
                        <li>優先サポート</li>
                        <li>カスタムインテグレーション</li>
                    </ul>
                    <a href="/login/" class="cta-button">選択する</a>
                </div>
                <div class="plan">
                    <h3>エンタープライズプラン</h3>
                    <div class="plan-price">要問合せ</div>
                    <ul class="plan-features">
                        <li>無制限ユーザーアカウント</li>
                        <li>無制限の質問</li>
                        <li>すべてのAI機能</li>
                        <li>24/7専用サポート</li>
                        <li>専用インスタンス</li>
                        <li>カスタムAIモデル</li>
                    </ul>
                    <a href="/login/" class="cta-button">お問い合わせ</a>
                </div>
            </div>
            <div class="demo-note">
                <p>※ デモ環境では、すべての機能を無料でお試しいただけます。</p>
            </div>
        </section>
    </div>

    <footer>
        <div class="container">
            <p>&copy; 2025 OpenHands SaaS. All rights reserved.</p>
        </div>
    </footer>
</body>
</html>
EOF

sudo chown -R nginx:nginx /var/www/html
```

### 3. OpenHandsインスタンスのセットアップ

#### 3.1 セットアップスクリプトの作成

```bash
cat << 'EOF' > openhands_setup.sh
#!/bin/bash
set -e
exec > >(tee -a ~/setup.log) 2>&1

IMAGE_TAG="0.30"
RUNTIME_IMAGE="docker.all-hands.dev/all-hands-ai/runtime:${IMAGE_TAG}-nikolaik"
APP_IMAGE="docker.all-hands.dev/all-hands-ai/openhands:${IMAGE_TAG}"

sudo amazon-linux-extras install docker -y
sudo systemctl enable docker
sudo systemctl start docker

sudo docker pull $RUNTIME_IMAGE
sudo docker pull $APP_IMAGE

sudo docker run -d --rm \
  -e SANDBOX_RUNTIME_CONTAINER_IMAGE=$RUNTIME_IMAGE \
  -e LOG_ALL_EVENTS=true \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ~/.openhands-state:/.openhands-state \
  -p 3000:3000 \
  --add-host host.docker.internal:host-gateway \
  --name openhands-app \
  $APP_IMAGE
EOF
```

#### 3.2 インスタンスへのスクリプト転送と実行

```bash
scp -o StrictHostKeyChecking=no -i ~/.ssh/openhands-key.pem openhands_setup.sh ec2-user@<INSTANCE_IP>:~/setup.sh
ssh -o StrictHostKeyChecking=no -i ~/.ssh/openhands-key.pem ec2-user@<INSTANCE_IP> "chmod +x ~/setup.sh && ~/setup.sh"
```

## トラブルシューティング

### 1. 502 Bad Gateway エラー

リバースプロキシサーバーがOpenHandsインスタンスに接続できない場合に発生します。

**解決策**:
- OpenHandsインスタンスが起動しているか確認
- セキュリティグループの設定を確認（ポート3000が開放されているか）
- Nginxの設定を確認

### 2. 404 Not Found エラー（/api/settings）

APIエンドポイントにアクセスできない場合に発生します。

**解決策**:
- Nginxの設定で `/api/` ロケーションが正しく設定されているか確認
- OpenHandsインスタンスが正常に動作しているか確認

### 3. WebSocket接続エラー

WebSocketの接続が拒否される場合に発生します。

**解決策**:
- Nginxの設定で `/socket.io/` ロケーションが正しく設定されているか確認
- WebSocketのプロキシ設定が正しいか確認

## ログイン情報

デモ環境では、以下のユーザーでログインできます：

- **インスタンス1**: user1 / password1
- **インスタンス2**: user2 / password2

## 注意事項

- このセットアップは開発・デモ用です。本番環境では、より堅牢な認証システムと永続的なセッション管理が必要です。
- セキュリティグループの設定は、必要最小限のポートのみを開放するように注意してください。
- SSL証明書は自己署名証明書を使用していますが、本番環境では正式な証明書を使用することをお勧めします。