/**
 * API Configuration
 * Nginx reverse proxy handles routing to microservices
 */

// API version prefix - application constant
const API_PREFIX = '/api/v1';

/**
 * Get API base URL - relative path since Nginx proxies
 * @returns {string} API prefix (e.g., "/api/v1")
 */
export const getApiBaseUrl = () => {
    // Use relative URLs - Nginx in same container will proxy
    return API_PREFIX;
};

/**
 * Get base domain (empty for relative URLs)
 * @returns {string} Empty string for relative URLs
 */
export const getBaseDomain = () => {
    return '';
};
