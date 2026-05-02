import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  root: '.',
  build: {
    outDir: 'dist',
  },
  server: {
    port: 5173,
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src-react/__tests__/setup.ts'],
    include: ['src-react/**/*.test.ts', 'src-react/**/*.test.tsx'],
    exclude: ['src-vanilla-archive/**', 'node_modules/**', 'dist/**'],
  },
});
