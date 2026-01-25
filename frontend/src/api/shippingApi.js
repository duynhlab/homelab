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
 * Estimate shipment cost (v1)
 * GET /api/v1/shipping/estimate?origin={origin}&destination={destination}&weight={weight}
 * @param {string} origin - Origin location
 * @param {string} destination - Destination location
 * @param {number} weight - Package weight in kg
 */
export async function estimateShipment(origin, destination, weight) {
    const response = await apiClient.get('/shipping/estimate', {
        params: { origin, destination, weight }
    });
    return response.data;
}
