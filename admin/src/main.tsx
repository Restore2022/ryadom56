import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App.tsx'
import './index.css'

function routerBasename(): string | undefined {
  if (typeof window === 'undefined') return undefined
  const path = window.location.pathname
  if (path === '/console' || path.startsWith('/console/')) return '/console'
  return undefined
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter basename={routerBasename()}>
      <App />
    </BrowserRouter>
  </StrictMode>,
)
