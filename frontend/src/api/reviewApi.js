import apiClient from './client';

/**
 * Review API
 * Consumes real backend API endpoints
 */

/**
 * Get reviews for a product
 * GET /api/v1/reviews?product_id={id}
 * @param {string} productId - Product ID to get reviews for
 */
export async function getReviews(productId) {
    const response = await apiClient.get('/reviews', {
        params: { product_id: productId }
    });
    return response.data;
}

/**
 * Create a new review
 * POST /api/v1/reviews
 * @param {string} productId - Product ID
 * @param {string} userId - User ID (from auth)
 * @param {number} rating - Rating (1-5)
 * @param {string} title - Review title
 * @param {string} comment - Review comment
 */
export async function createReview(productId, userId, rating, title, comment) {
    const response = await apiClient.post('/reviews', {
        product_id: productId,
        user_id: userId,
        rating,
        title,
        comment
    });
    return response.data;
}
