import { createContext, useContext, useReducer, useCallback } from 'react';
import ToastViewport from './ToastViewport';

/**
 * Global Toast Notification System
 * 
 * Usage:
 *   const { notify } = useToast();
 *   notify('success', 'Item added to cart');
 *   notify('error', 'Failed to save');
 *   notify('info', 'You already reviewed this product');
 * 
 * Options:
 *   notify('success', 'Message', { duration: 5000 }); // custom duration in ms
 */

const ToastContext = createContext(null);

// Toast reducer for managing the queue
function toastReducer(state, action) {
    switch (action.type) {
        case 'ADD':
            // Keep max 5 toasts, drop oldest if exceeded
            const newToasts = [...state, action.toast];
            return newToasts.length > 5 ? newToasts.slice(-5) : newToasts;
        case 'REMOVE':
            return state.filter(t => t.id !== action.id);
        case 'CLEAR':
            return [];
        default:
            return state;
    }
}

let toastId = 0;

export function ToastProvider({ children }) {
    const [toasts, dispatch] = useReducer(toastReducer, []);

    const notify = useCallback((type, message, options = {}) => {
        const id = ++toastId;
        const duration = options.duration ?? 4000; // 4s default

        const toast = {
            id,
            type, // 'success' | 'error' | 'info'
            message,
            duration,
        };

        dispatch({ type: 'ADD', toast });

        // Auto-dismiss
        if (duration > 0) {
            setTimeout(() => {
                dispatch({ type: 'REMOVE', id });
            }, duration);
        }

        return id;
    }, []);

    const dismiss = useCallback((id) => {
        dispatch({ type: 'REMOVE', id });
    }, []);

    const clearAll = useCallback(() => {
        dispatch({ type: 'CLEAR' });
    }, []);

    const value = {
        toasts,
        notify,
        dismiss,
        clearAll,
    };

    return (
        <ToastContext.Provider value={value}>
            {children}
            <ToastViewport toasts={toasts} onDismiss={dismiss} />
        </ToastContext.Provider>
    );
}

export function useToast() {
    const context = useContext(ToastContext);
    if (!context) {
        throw new Error('useToast must be used within a ToastProvider');
    }
    return context;
}

export default ToastProvider;
