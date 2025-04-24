/// <reference types="vitest" />
/// <reference types="vite-plugin-svgr/client" />
import { defineConfig, loadEnv } from "vite";
import viteTsconfigPaths from "vite-tsconfig-paths";
import svgr from "vite-plugin-svgr";
import { reactRouter } from "@react-router/dev/vite";
import { configDefaults } from "vitest/config";

export default defineConfig(({ mode }) => {
  const {
    VITE_BACKEND_HOST = "127.0.0.1:3000",
    VITE_USE_TLS = "false",
    VITE_FRONTEND_PORT = "3001",
    VITE_INSECURE_SKIP_VERIFY = "false",
    VITE_ALLOW_IFRAME = "true",
  } = loadEnv(mode, process.cwd());

  const USE_TLS = VITE_USE_TLS === "true";
  const INSECURE_SKIP_VERIFY = VITE_INSECURE_SKIP_VERIFY === "true";
  const ALLOW_IFRAME = VITE_ALLOW_IFRAME === "true";
  const PROTOCOL = USE_TLS ? "https" : "http";
  const WS_PROTOCOL = USE_TLS ? "wss" : "ws";

  const API_URL = `${PROTOCOL}://${VITE_BACKEND_HOST}/`;
  const WS_URL = `${WS_PROTOCOL}://${VITE_BACKEND_HOST}/`;
  const FE_PORT = Number.parseInt(VITE_FRONTEND_PORT, 10);

  return {
    plugins: [
      !process.env.VITEST && reactRouter(),
      viteTsconfigPaths(),
      svgr(),
    ],
    server: {
      port: FE_PORT,
      host: "0.0.0.0", // Allow connections from any host
      proxy: {
        "/api": {
          target: API_URL,
          changeOrigin: true,
          secure: !INSECURE_SKIP_VERIFY,
        },
        "/ws": {
          target: WS_URL,
          ws: true,
          changeOrigin: true,
          secure: !INSECURE_SKIP_VERIFY,
        },
        "/socket.io": {
          target: WS_URL,
          ws: true,
          changeOrigin: true,
          secure: !INSECURE_SKIP_VERIFY,
        },
      },
      watch: {
        ignored: ['**/node_modules/**', '**/.git/**'],
      },
      headers: ALLOW_IFRAME ? {
        // Allow embedding in iframes
        "Content-Security-Policy": "frame-ancestors 'self' *",
        "X-Frame-Options": "ALLOWALL",
      } : {},
      cors: {
        origin: "*", // Allow CORS from any origin
        methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allowedHeaders: ["Content-Type", "Authorization"],
        credentials: true,
      },
    },
    build: {
      // Optimize build for production
      target: "esnext",
      minify: "terser",
      terserOptions: {
        compress: {
          drop_console: mode === "production",
          drop_debugger: mode === "production",
        },
      },
      rollupOptions: {
        output: {
          manualChunks: {
            // Split vendor code into separate chunks
            vendor: [
              'react', 
              'react-dom', 
              'react-router', 
              '@reduxjs/toolkit', 
              'react-redux'
            ],
            monaco: ['monaco-editor', '@monaco-editor/react'],
            ui: ['@heroui/react', 'framer-motion', 'react-icons'],
          },
        },
      },
      // Enable source maps for debugging
      sourcemap: mode !== "production",
    },
    optimizeDeps: {
      // Optimize dependencies for faster startup
      include: [
        'react', 
        'react-dom', 
        'react-router', 
        '@reduxjs/toolkit', 
        'react-redux',
        '@monaco-editor/react',
      ],
      esbuildOptions: {
        target: 'esnext',
      },
    },
    ssr: {
      noExternal: ["react-syntax-highlighter"],
    },
    clearScreen: false,
    test: {
      environment: "jsdom",
      setupFiles: ["vitest.setup.ts"],
      exclude: [...configDefaults.exclude, "tests"],
      coverage: {
        reporter: ["text", "json", "html", "lcov", "text-summary"],
        reportsDirectory: "coverage",
        include: ["src/**/*.{ts,tsx}"],
      },
    },
  };
});
