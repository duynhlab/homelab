import apiClient from './client';
import { USE_MOCK } from './config';
import { MOCK_PRODUCTS, getMockProductDetails } from './mockData';

/**
 * Product API
 * Supports mock mode (local build/test) and real API (production)
 */

/**
 * Get all products
 * GET /api/v1/products
 */
export async function getProducts() {
    if (USE_MOCK) {
        console.log('🎭 Mock mode: Returning mock products');
        return Promise.resolve(MOCK_PRODUCTS);
    }
    const response = await apiClient.get('/products');
    return response.data;
}

/**
 * Get single product by ID (basic)
 * GET /api/v1/products/:id
 */
export async function getProduct(id) {
    if (USE_MOCK) {
        console.log(`🎭 Mock mode: Returning mock product ${id}`);
        const product = MOCK_PRODUCTS.find(p => p.id === id);
        return Promise.resolve(product || null);
    }
    const response = await apiClient.get(`/products/${id}`);
    return response.data;
}

/**
 * Get aggregated product details (Phase 1 aggregation endpoint)
 * GET /api/v1/products/:id/details
 */
export async function getProductDetails(id) {
    if (USE_MOCK) {
        console.log(`🎭 Mock mode: Returning mock product details ${id}`);
        return Promise.resolve(getMockProductDetails(id));
    }
    const response = await apiClient.get(`/products/${id}/details`);
    return response.data;
}
