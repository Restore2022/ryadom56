import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig(({ command }) => ({
  plugins: [react()],
  // Относительные ассеты: админка живёт и на / (пока nginx не сменили), и на /console/.
  base: command === 'build' ? './' : '/',
}))
