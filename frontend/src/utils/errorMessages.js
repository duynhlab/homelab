/**
 * Maps backend/API errors to user-friendly messages.
 * Never expose raw backend errors to users (security + UX).
 */

const USER_FRIENDLY_MAP = {
    'Internal server error': 'Something went wrong. Please try again later.',
    'Authentication required': 'Please log in to continue.',
    'Invalid or expired token': 'Your session has expired. Please log in again.',
    'Invalid order': 'Please check your order and try again.',
    'User not found': 'Profile not found.',
    'User already exists': 'This account already exists.',
    'Invalid email address': 'Please enter a valid email address.',
    'Unauthorized access': 'You do not have permission to perform this action.',
    'Order not found': 'Order not found.',
    'Network error. Please check your connection.': 'Connection error. Please check your network and try again.',
};

/**
 * Returns a user-friendly error message for display in UI.
 * Falls back to generic message for unknown errors.
 */
export function toUserFriendlyError(rawError) {
    if (!rawError || typeof rawError !== 'string') {
        return 'Something went wrong. Please try again.';
    }
    const trimmed = rawError.trim();
    return USER_FRIENDLY_MAP[trimmed] || 'Something went wrong. Please try again.';
}
