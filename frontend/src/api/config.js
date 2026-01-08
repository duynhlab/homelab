/**
 * API Configuration
 * Build-time configuration via Vite environment variables
 */

// API version prefix - application constant
const API_PREFIX = '/api/v1';

// Check if API URL is configured
const apiBaseUrl = import.meta.env.VITE_API_BASE_URL || '';

// Check explicit mock flag
const useMockFlag = import.meta.env.VITE_USE_MOCK;

/**
 * USE_MOCK: Determined by explicit flag or API URL presence
 * Priority:
 * 1. VITE_USE_MOCK=true → Force mock mode
 * 2. VITE_USE_MOCK=false → Force real API (requires VITE_API_BASE_URL)
 * 3. Not set → Auto-detect (mock if no VITE_API_BASE_URL)
 */
export const USE_MOCK = useMockFlag === 'true' || (!useMockFlag && !apiBaseUrl);

/**
 * Get API base URL from build-time environment variable
 * Set via VITE_API_BASE_URL during docker build
 * 
 * @returns {string} Full API base URL (e.g., "http://localhost:8080/api/v1")
 */
export const getApiBaseUrl = () => {
    if (USE_MOCK) {
        console.warn('🎭 Mock mode enabled');
        return 'MOCK_MODE';
    }

    if (!apiBaseUrl) {
        console.error('❌ VITE_API_BASE_URL not set but mock mode is disabled');
        throw new Error('API_BASE_URL required when VITE_USE_MOCK=false');
    }

    // Remove trailing slash and append API prefix
    return `${apiBaseUrl.replace(/\/$/, '')}${API_PREFIX}`;
};

/**
 * Get base domain (without /api/v1 prefix)
 */
export const getBaseDomain = () => {
    return USE_MOCK ? 'MOCK_MODE' : apiBaseUrl;
};
