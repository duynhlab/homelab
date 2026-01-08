/**
 * API Configuration
 * Build-time configuration via Vite environment variables
 */

// API version prefix - application constant
const API_PREFIX = '/api/v1';

/**
 * Get API base URL from build-time environment variable
 * Set via VITE_API_BASE_URL during docker build
 * 
 * @returns {string} Full API base URL (e.g., "http://localhost:8080/api/v1")
 * @throws {Error} If VITE_API_BASE_URL is not set
 */
export const getApiBaseUrl = () => {
    const apiBaseUrl = import.meta.env.VITE_API_BASE_URL;
    
    if (!apiBaseUrl) {
        throw new Error('VITE_API_BASE_URL is required for production build');
    }

    // Remove trailing slash and append API prefix
    return `${apiBaseUrl.replace(/\/$/, '')}${API_PREFIX}`;
};

/**
 * Get base domain (without /api/v1 prefix)
 * 
 * @returns {string} Base API domain (e.g., "http://localhost:8080")
 * @throws {Error} If VITE_API_BASE_URL is not set
 */
export const getBaseDomain = () => {
    const apiBaseUrl = import.meta.env.VITE_API_BASE_URL;
    
    if (!apiBaseUrl) {
        throw new Error('VITE_API_BASE_URL is required for production build');
    }
    
    return apiBaseUrl;
};
