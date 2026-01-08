import apiClient from './client';
import { USE_MOCK } from './config';

/**
 * Cart API
 * Supports mock mode (local build/test) and real API (production)
 */

/**
 * GET /api/v1/cart - Get full cart
 */
export async function getCart() {
    if (USE_MOCK) {
        console.log('🎭 Mock mode: Returning empty cart');
        return Promise.resolve({
            id: 'cart123',
            user_id: 'user456',
            items: [],
            subtotal: 0,
            shipping: 5.00,
            total: 5.00,
            item_count: 0
        });
    }
    const response = await apiClient.get('/cart');
    return response.data;
}

/**
 * GET /api/v1/cart/count - Get cart item count (for badge)
 */
export async function getCartCount() {
    if (USE_MOCK) {
        console.log('🎭 Mock mode: Returning cart count 0');
        return Promise.resolve({ count: 0 });
    }
    const response = await apiClient.get('/cart/count');
    return response.data;
}

/**
 * POST /api/v1/cart - Add item to cart
 */
export async function addToCart(productId, quantity = 1) {
    if (USE_MOCK) {
        console.log(`🎭 Mock mode: Simulating add to cart (${productId}, ${quantity})`);
        return Promise.resolve({ message: 'Item added to cart' });
    }
    const response = await apiClient.post('/cart', {
        product_id: productId,
        quantity
    });
    return response.data;
}

/**
 * PATCH /api/v1/cart/items/:itemId - Update cart item quantity
 */
export async function updateCartItem(itemId, quantity) {
    if (USE_MOCK) {
        console.log(`🎭 Mock mode: Simulating update cart item (${itemId}, ${quantity})`);
        return Promise.resolve({ success: true });
    }
    const response = await apiClient.patch(`/cart/items/${itemId}`, { quantity });
    return response.data;
}

/**
 * DELETE /api/v1/cart/items/:itemId - Remove item from cart
 */
export async function removeCartItem(itemId) {
    if (USE_MOCK) {
        console.log(`🎭 Mock mode: Simulating remove cart item (${itemId})`);
        return Promise.resolve({ success: true });
    }
    const response = await apiClient.delete(`/cart/items/${itemId}`);
    return response.data;
}
