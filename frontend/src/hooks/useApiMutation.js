import { useState, useCallback } from 'react';
import { useToast } from '../components/common/ToastProvider';

/**
 * useApiMutation Hook
 * Standard mutation wrapper with loading state and optional toast notifications
 * 
 * Usage:
 *   const { mutate, loading, error } = useApiMutation(updateProfile, {
 *     onSuccess: () => console.log('Updated!'),
 *     successMessage: 'Profile updated!',
 *     errorMessage: 'Failed to update profile',
 *   });
 *   
 *   const handleSubmit = async (data) => {
 *     const result = await mutate(data);
 *     if (result) { // success }
 *   };
 * 
 * @param {function} mutationFn - Async function to call
 * @param {object} options - Configuration options
 */
export function useApiMutation(mutationFn, options = {}) {
    const {
        onSuccess,
        onError,
        successMessage,
        errorMessage,
        showToast: enableToast = true,
    } = options;

    const { notify } = useToast();
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);

    const mutate = useCallback(async (...args) => {
        setLoading(true);
        setError(null);

        try {
            const result = await mutationFn(...args);
            
            if (enableToast && successMessage) {
                notify('success', successMessage);
            }
            
            if (onSuccess) {
                onSuccess(result);
            }
            
            return result;
        } catch (err) {
            const message = err?.message || errorMessage || 'An error occurred';
            setError(message);
            
            if (enableToast) {
                notify('error', errorMessage || message);
            }
            
            if (onError) {
                onError(err);
            }
            
            return null;
        } finally {
            setLoading(false);
        }
    }, [mutationFn, onSuccess, onError, successMessage, errorMessage, enableToast, notify]);

    const reset = useCallback(() => {
        setError(null);
    }, []);

    return {
        mutate,
        loading,
        error,
        reset,
    };
}

export default useApiMutation;
