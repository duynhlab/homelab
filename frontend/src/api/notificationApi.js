import apiClient from './client';

/**
 * Notification API (v2 endpoints)
 * Consumes real backend API endpoints
 */

/**
 * Get all notifications for current user
 * GET /api/v2/notifications
 */
export async function getNotifications() {
    const response = await apiClient.get('/api/v2/notifications');
    return response.data;
}

/**
 * Get notification by ID
 * GET /api/v2/notifications/:id
 * @param {string} id - Notification ID
 */
export async function getNotification(id) {
    const response = await apiClient.get(`/api/v2/notifications/${id}`);
    return response.data;
}

/**
 * Mark notification as read
 * PATCH /api/v2/notifications/:id
 * @param {string} id - Notification ID
 */
export async function markAsRead(id) {
    const response = await apiClient.patch(`/api/v2/notifications/${id}`, {
        read: true
    });
    return response.data;
}
