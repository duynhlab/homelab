import apiClient from './client';

/**
 * Cart API
 * Consumes real backend API endpoints
 */

/**
 * GET /api/v1/cart - Get full cart
 */
export async function getCart() {
    const response = await apiClient.get('/cart');
    return response.data;
}

/**
 * GET /api/v1/cart/count - Get cart item count (for badge)
 */
export async function getCartCount() {
    const response = await apiClient.get('/cart/count');
    return response.data;
}

/**
 * POST /api/v1/cart - Add item to cart
 */
export async function addToCart(productId, productName, productPrice, quantity = 1) {
    const response = await apiClient.post('/cart', {
        product_id: productId,
        product_name: productName,
        product_price: productPrice,
        quantity
    });
    return response.data;
}

/**
 * PATCH /api/v1/cart/items/:itemId - Update cart item quantity
 */
export async function updateCartItem(itemId, quantity) {
    const response = await apiClient.patch(`/cart/items/${itemId}`, { quantity });
    return response.data;
}

/**
 * DELETE /api/v1/cart/items/:itemId - Remove item from cart
 */
export async function removeCartItem(itemId) {
    const response = await apiClient.delete(`/cart/items/${itemId}`);
    return response.data;
}

/**
 * DELETE /api/v1/cart - Clear all cart items
 */
export async function clearCart() {
    const response = await apiClient.delete('/cart');
    return response.data;
}
