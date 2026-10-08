import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    // `vite dev` only. In the container, nginx proxies /api to the backend, and
    // in Kubernetes the Ingress does it -- so the browser always sees one
    // origin and the frontend never needs to know a backend hostname.
    proxy: { '/api': 'http://localhost:8000' },
  },
  build: { outDir: 'dist', sourcemap: false },
})
