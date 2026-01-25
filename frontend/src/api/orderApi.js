import apiClient from './client';

/**
 * Order API
 * Consumes real backend API endpoints
 */

/**
 * GET /api/v1/orders - List user orders
 */
export async function getOrders() {
    const response = await apiClient.get('/orders');
    return response.data;
}

/**
 * GET /api/v1/orders/:id - Get order by ID
 */
export async function getOrder(id) {
    const response = await apiClient.get(`/orders/${id}`);
    return response.data;
}

/**
 * GET /api/v1/orders/:id/details - Get order with shipment info (aggregation)
 * Returns: { order, shipment? }
 */
export async function getOrderDetails(id) {
    const response = await apiClient.get(`/orders/${id}/details`);
    return response.data;
}

/**
 * POST /api/v1/orders - Create new order
 */
export async function createOrder(orderData) {
    const response = await apiClient.post('/orders', orderData);
    return response.data;
}
