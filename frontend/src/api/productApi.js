import apiClient from './client';

/**
 * Product API
 * Consumes real backend API endpoints
 */

/**
 * Get all products
 * GET /api/v1/products
 */
export async function getProducts(params = {}) {
    const response = await apiClient.get('/products', { params });
    // Response format: { items: [], total: number }
    return response.data;
}

/**
 * Get single product by ID (basic)
 * GET /api/v1/products/:id
 */
export async function getProduct(id) {
    const response = await apiClient.get(`/products/${id}`);
    return response.data;
}

/**
 * Get aggregated product details (Phase 1 aggregation endpoint)
 * GET /api/v1/products/:id/details
 */
export async function getProductDetails(id) {
    const response = await apiClient.get(`/products/${id}/details`);
    return response.data;
}
