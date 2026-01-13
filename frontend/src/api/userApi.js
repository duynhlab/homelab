import apiClient from './client';

/**
 * User API
 * Consumes real backend API endpoints
 */

/**
 * Get current user profile
 * GET /api/v1/users/profile
 */
export async function getUserProfile() {
    const response = await apiClient.get('/users/profile');
    return response.data;
}

/**
 * Get user by ID
 * GET /api/v1/users/:id
 * @param {string} id - User ID
 */
export async function getUser(id) {
    const response = await apiClient.get(`/users/${id}`);
    return response.data;
}

/**
 * Update user profile
 * PUT /api/v1/users/profile
 * @param {object} profileData - Profile data to update
 */
export async function updateProfile(profileData) {
    const response = await apiClient.put('/users/profile', profileData);
    return response.data;
}
