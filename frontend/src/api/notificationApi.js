import apiClient from './client';

/**
 * Notification API (v1 endpoints)
 * Consumes real backend API endpoints
 */

/**
 * Get all notifications for current user
 * GET /api/v1/notifications
 */
export async function getNotifications() {
    const response = await apiClient.get('/notifications');
    return response.data;
}

/**
 * Get notification by ID
 * GET /api/v1/notifications/:id
 * @param {string} id - Notification ID
 */
export async function getNotification(id) {
    const response = await apiClient.get(`/notifications/${id}`);
    return response.data;
}

/**
 * Mark notification as read
 * PATCH /api/v1/notifications/:id
 * @param {string} id - Notification ID
 */
export async function markAsRead(id) {
    const response = await apiClient.patch(`/notifications/${id}`);
    return response.data;
}
