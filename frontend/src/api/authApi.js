import apiClient from './client';

/**
 * Auth API
 * Consumes real backend API endpoints
 */

/**
 * POST /api/v1/auth/login
 * @param {string} email - User email (matches seed data: alice@example.com)
 * @param {string} password - User password
 */
export async function login(email, password) {
    const response = await apiClient.post('/auth/login', { email, password });
    return response.data;
}

/**
 * POST /api/v1/auth/register
 */
export async function register(username, email, password) {
    const response = await apiClient.post('/auth/register', { username, email, password });
    return response.data;
}
