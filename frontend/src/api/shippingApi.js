import apiClient from './client';

/**
 * Shipping API
 * Consumes real backend API endpoints
 */

/**
 * Track shipment by tracking number
 * GET /api/v1/shipping/track?tracking_number={number}
 * @param {string} trackingNumber - Shipment tracking number
 */
export async function trackShipment(trackingNumber) {
    const response = await apiClient.get('/shipping/track', {
        params: { tracking_number: trackingNumber }
    });
    return response.data;
}

/**
 * Estimate shipment cost (v2)
 * GET /api/v2/shipments/estimate?weight={weight}&destination={destination}
 * @param {number} weight - Package weight
 * @param {string} destination - Destination code (e.g., 'US')
 */
export async function estimateShipment(weight, destination) {
    const response = await apiClient.get('/api/v2/shipments/estimate', {
        params: { weight, destination }
    });
    return response.data;
}
