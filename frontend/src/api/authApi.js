import apiClient from './client';

/**
 * Auth API
 * Consumes real backend API endpoints
 */

/**
 * POST /api/v1/auth/login
 */
export async function login(username, password) {
    const response = await apiClient.post('/auth/login', { username, password });
    return response.data;
}

/**
 * POST /api/v1/auth/register
 */
export async function register(username, email, password) {
    const response = await apiClient.post('/auth/register', { username, email, password });
    return response.data;
}
