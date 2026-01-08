import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import './index.css'
import { getBaseDomain, getApiBaseUrl } from './api/config'

// Log API configuration at startup
console.log('🚀 Frontend Starting...');
console.log('📡 API Base Domain:', getBaseDomain());
try {
    const fullApiUrl = getApiBaseUrl();
    console.log('✅ API Full URL:', fullApiUrl);
} catch (error) {
    console.error('❌ Failed to initialize API configuration:', error.message);
}

ReactDOM.createRoot(document.getElementById('root')).render(
    <React.StrictMode>
        <BrowserRouter>
            <App />
        </BrowserRouter>
    </React.StrictMode>,
)
