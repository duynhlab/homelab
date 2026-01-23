import useSWR from 'swr';
import { getProducts } from '../api/productApi';

/**
 * Custom hook for fetching products with SWR
 * SWR provides automatic request deduplication, caching, and revalidation
 * NOTE: No filter support - API doesn't have search/filter
 */
export function useProducts() {
    const { data, error, isLoading } = useSWR('products', getProducts, {
        revalidateOnFocus: false,
        dedupingInterval: 2000, // Dedupe requests within 2s
        revalidateOnReconnect: true,
    });

    return {
        products: Array.isArray(data) ? data : [],
        loading: isLoading,
        error: error?.message || null,
    };
}
